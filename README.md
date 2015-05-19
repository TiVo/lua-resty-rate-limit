## OpenResty Redis Backed Rate Limiter
This is a OpenResty Lua and Redis powered rate limiter. You can specify the number of requests to allow within a certain timespan, ie. 40 requests within 10 seconds. With this setting (as an example), you can burst to 40 requests in a single second if you wanted, but would have to wait 9 more seconds before being allowed to issue another.

### OpenResty Prerequisite
You have to compile OpenResty with the `--with-http_realip_module` option.

### Needed in your nginx.conf
```
http {
    # http://serverfault.com/questions/331531/nginx-set-real-ip-from-aws-elb-load-balancer-address
    # http://serverfault.com/questions/331697/ip-range-for-internal-private-ip-of-amazon-elb
    set_real_ip_from            127.0.0.1;
    set_real_ip_from            10.0.0.0/8;
    set_real_ip_from            172.16.0.0/12;
    set_real_ip_from            192.168.0.0/16;
    real_ip_header              X-Forwarded-For;
    real_ip_recursive           on;
}
```

### Example OpenResty Site Config
```
# Location of this Lua package
lua_package_path "/opt/lua-resty-rate-limit/lib/?.lua;;";

upstream api {
    server unix:/run/api.sock;
}

server {
    listen 80;
    server_name api.dev;

    access_log  /var/log/openresty/api_access.log;
    error_log   /var/log/openresty/api_error.log;

    location / {
        access_by_lua '
            local request = require "resty.rate.limit"
            request.limit { key = ngx.var.remote_addr,
                            rate = 40,
                            interval = 10,
                            log_level = ngx.NOTICE,
                            redis_config = { host = "127.0.0.1", port = 6379, timeout = 1, pool_size = 100 } }
        ';

        proxy_set_header  Host               $host;
        proxy_set_header  X-Server-Scheme    $scheme;
        proxy_set_header  X-Real-IP          $remote_addr;
        proxy_set_header  X-Forwarded-For    $remote_addr;
        proxy_set_header  X-Forwarded-Proto  $x_forwarded_proto;

        proxy_connect_timeout  1s;
        proxy_read_timeout     30s;

        proxy_pass   http://api;
    }
}
```

### Config Values
You can customize the rate limiting options by changing the following values:

* key: The value to use as a unique identifier in Redis.
* rate: The number of requests to allow within the specified interval
* interval: The number of seconds before the bucket expires
* log_level: Set an Nginx log level. All errors from this plugin will be dumped here
* redis_config: The Redis host and port to connect to
