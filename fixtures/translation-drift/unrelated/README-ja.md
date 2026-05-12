# pyramid-cache

Redis 互換のキャッシュサーバ実装、永続化レイヤと PubSub をサポートします。

## 起動

```bash
docker run -p 6379:6379 pyramid-cache:latest
```

## 接続

```python
import redis

r = redis.Redis(host="localhost", port=6379)
r.set("foo", "bar")
```

## ライセンス

Apache 2.0。
