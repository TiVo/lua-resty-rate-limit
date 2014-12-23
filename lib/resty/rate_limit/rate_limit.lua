local function bump_request(connection, key, rate, duration)
    local redis_connection = connection

    count, err = redis_connection.incr(key)
    if not count then
        ngx.log(log_level, "failed to incr count: ", err)
        return
    end

    if tonumber(count) == 1 then
        redis.expire(key,10)
    end

    -- put it into the connection pool of size 100,
    -- with 10 seconds max idle timeout
    local ok, error = redis_connection:set_keepalive(10000, 100)
    if not ok then
        ngx.log(ngx.WARN, "failed to set keepalive: ", error)
    end

    return count
end

function _M.limit(config)
    if not config.connection then
        local ok, redis = pcall(require, "resty.redis")
        if not ok then
            ngx.log(ngx.error, "failed to require redis")
            return _M.OK
        end

        local redis_config = config.redis_config or {}
        redis_config.timeout = redis_config.timeout or 1
        redis_config.host = redis_config.host or "127.0.0.1"
        redis_config.port = redis_config.port or 6379

        local redis_connection = redis:new()
        redis_connection:set_timeout(redis_config.timeout * 1000)

        local ok, error = redis_connection:connect(redis_config.host, redis_config.port)
        if not ok then
            ngx.log(ngx.WARN, "redis connect error: ", error)
            return _M.OK
        end

        config.connection = redis_connection
    end

    local connection = config.connection
    local key = config.key or ngx.var.remote_addr
    local rate = config.rate or 10
    local interval = config.interval or 0
    local log_level = config.log_level or ngx.NOTICE

    local response, error = bump_request(connection, key, rate, interval)
    return response
    -- if response and (response[1] == _M.BUSY or response[1] == _M.FORBIDDEN) then
    --     if response[1] == _M.BUSY then
    --         ngx.log(log_level, response[0])
    --         ngx.log(log_level, 'limiting requests, excess ' ..
    --                     response[2]/1000 .. ' by zone "' .. zone .. '"')
    --     end
    --     return
    -- end

    if not response and error then
        ngx.log(ngx.WARN, "redis lookup error: ", error)
    end
    -- return _M.OK
end


-- return _M
