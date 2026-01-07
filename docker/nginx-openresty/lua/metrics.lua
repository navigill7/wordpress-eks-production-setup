local dict = ngx.shared.metrics
ngx.say("# TYPE nginx_requests_total counter")
ngx.say("nginx_requests_total ", dict:get("requests") or 0)
