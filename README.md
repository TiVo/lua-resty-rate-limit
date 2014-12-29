## OpenResty Redis Backed Rate Limiter
This is a OpenResty Lua powered rate limiter.

### Example OpenResty Config
```
# Location of the Lua rate-limit package
lua_package_path "/Users/travisbell/workspace/lua-resty-rate-limit/lib/?.lua;;";

upstream api {
  server unix:/var/run/api/api.sock;
}

server {
  listen 80;
  server_name api.dev;

  #access_log   /etc/openresty/logs/tmdb-api_access.log detailed;
  error_log    /etc/openresty/logs/tmdb-api_error.log notice;

  location / {
    access_by_lua '
      local request = require "resty.rate.limit"
      request.limit { key = ngx.var.remote_addr,
                      rate = 40,
                      interval = 10,
                      log_level = ngx.NOTICE,
                      redis = { host = "127.0.0.1", port = 6379 } }
    ';

    include      proxy.incl;
    proxy_pass   http://api;
  }

}
```

### Config Values
You can customize the rate limiting options by changing the following values:

* key: The value to use as a unique identifier in Redis.
* rate: The number of requests to allow within the specififed interval
* interval: The number of seconds before the bucket expires
* log_level: Set an Nginx log level. All errors from this plugin will be dumped here
* redis: The Redis host and port to connect to