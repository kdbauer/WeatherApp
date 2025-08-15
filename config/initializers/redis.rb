require "redis"

# Configure Redis connection
REDIS_CLIENT = Redis.new(
  url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0"),
  reconnect_attempts: 3
)

# Test Redis connection on startup
begin
  REDIS_CLIENT.ping
  Rails.logger.info "✅ Redis connection established successfully"
rescue Redis::BaseError => e
  Rails.logger.warn "⚠️  Redis connection failed: #{e.message}"
  Rails.logger.warn "Weather caching will be disabled"
end
