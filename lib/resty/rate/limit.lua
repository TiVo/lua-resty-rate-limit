_M = { _VERSION = "1.0" }

local reset = 0

local function expire_key(redis_connection, key, interval)
    local expire, error = redis_connection:expire(key, interval)
    if not expire then
        ngx.log(log_level, "failed to get ttl: ", error)
        return
    end
end

local function bump_request(connection, key, rate, interval, current_time, log_level)
    local redis_connection = connection

    local count, error = redis_connection:incr(key)
    if not count then
        ngx.log(log_level, "failed to incr count: ", error)
        return
    end

    if tonumber(count) == 1 then
        local reset = math.floor(current_time) + interval
        expire_key(redis_connection, key, interval)
    else
        local ttl, error = redis_connection:ttl(key)
        if not ttl then
            ngx.log(log_level, "failed to get ttl: ", error)
            return
        end
        if ttl == -1 then
            ttl = interval
            expire_key(redis_connection, key, interval)
        end
        local reset = math.floor(current_time) + ttl
    end

    local ok, error = redis_connection:set_keepalive(10000, 8)
    if not ok then
        ngx.log(log_level, "failed to set keepalive: ", error)
    end

    local remaining = rate - count

    return { count = count, remaining = remaining, reset = reset }
end

function _M.limit(config)
    local log_level = config.log_level or ngx.NOTICE

    if not config.connection then
        local ok, redis = pcall(require, "resty.redis")
        if not ok then
            ngx.log(log_level, "failed to require redis")
            return
        end

        local redis_config = config.redis_config or {}
        redis_config.timeout = redis_config.timeout or 1
        redis_config.host = redis_config.host or "127.0.0.1"
        redis_config.port = redis_config.port or 6379

        local redis_connection = redis:new()
        redis_connection:set_timeout(redis_config.timeout * 1000)

        local ok, error = redis_connection:connect(redis_config.host, redis_config.port)
        if not ok then
            ngx.log(log_level, "failed to connect to redis: ", error)
            return
        end

        config.connection = redis_connection
    end

    local current_time = ngx.now()
    local connection = config.connection
    local key = config.key or ngx.var.remote_addr
    local rate = config.rate or 10
    local interval = config.interval or 1

    local response, error = bump_request(connection, key, rate, interval, current_time, log_level)
    if not response then
        return
    end

    local retry_after = math.floor(response.reset - current_time)
    if retry_after < 0 then
        retry_after = 0
    end

    if response.count > rate then
        ngx.header["Access-Control-Allow-Origin"] = "*"
        ngx.header["Content-Type"] = "application/json; charset=utf-8"
        ngx.header["Retry-After"] = retry_after
        ngx.status = 429
        ngx.say('{"status_code":25,"status_message":"Your request count (' .. response.count .. ') is over the allowed limit of ' .. rate .. '."}')
        ngx.exit(ngx.HTTP_OK)
    else
        ngx.header["X-RateLimit-Limit"] = rate
        ngx.header["X-RateLimit-Remaining"] = math.floor(response.remaining)
        ngx.header["X-RateLimit-Reset"] = response.reset
    end
end

return _M
