# Performance Checklist

Improve continuously; don't gold-plate prematurely. Profile before optimizing.

## Backend (Django)
- **Queries** — eliminate N+1 with `select_related` / `prefetch_related`; add indexes for filtered/ordered columns
- **API latency** — paginate list endpoints; avoid serializing more than the client needs
- **Caching** — cache expensive reads with sane invalidation
- **Background processing** — push slow work (emails, exports, notifications) to async tasks

## Flutter
- **Widget rebuilds** — scope `setState` / rebuilds narrowly; use `const` constructors
- **Memory** — dispose controllers, cancel subscriptions
- **Image loading** — cached network images, correct resolution, no full-size loads in lists
- **Startup time** — defer non-critical init off the first frame
- **Network** — batch where possible, handle slow/offline gracefully, paginate lists
