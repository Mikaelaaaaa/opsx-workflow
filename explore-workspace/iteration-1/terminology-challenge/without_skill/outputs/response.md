# Adding Users and Admin Access to the Todo API

## What was done

The codebase was a minimal Express todo API with a single in-memory array and no authentication. I added:

1. **Shared in-memory store** (`src/data/store.js`) — holds the `users` list and `todos` array so both route files share the same data.

2. **Auth middleware** (`src/middleware/auth.js`) — reads the `X-User-Id` request header and attaches the matching user to `req.user`. Returns 401 if the header is missing, 403 if the user ID is unknown.

3. **User route** (`src/routes/users.js`) — two endpoints:
   - `GET /api/users` — admin-only list of all users
   - `GET /api/users/me` — returns the current user's profile

4. **Todos route updated** (`src/routes/todos.js`) — all endpoints now require auth:
   - `GET /api/todos` — admins see every todo; regular users see only their own
   - `POST /api/todos` — todo is stamped with `ownerId: req.user.id`
   - `PATCH /api/todos/:id` — owner or admin can edit; clients cannot change `ownerId`
   - `DELETE /api/todos/:id` — owner or admin can delete

5. **`src/index.js`** updated to mount `/api/users`.

## Design decisions (defaults chosen)

| Question | Default chosen | Rationale |
|---|---|---|
| Auth mechanism | `X-User-Id` header | Simplest possible — no password/JWT complexity needed for this prototype |
| Seed users | alice (admin), bob, carol (regular) | Gives something to test with immediately |
| Can admin create todos for others? | No — `ownerId` is always the requester | Keeps it simple; easy to relax later |
| Changing `ownerId` via PATCH? | Stripped silently | Prevents privilege escalation without an error response that leaks info |

## Files changed

| File | Change |
|---|---|
| `src/data/store.js` | New — shared in-memory store with seeded users |
| `src/middleware/auth.js` | New — `requireAuth` middleware |
| `src/routes/users.js` | New — `/api/users` and `/api/users/me` endpoints |
| `src/routes/todos.js` | Rewritten — ownership + admin visibility |
| `src/index.js` | Updated — mounts `/api/users` router |

## Example usage

```bash
# Bob creates a todo (ownerId=2)
curl -s -X POST http://localhost:3000/api/todos \
  -H "Content-Type: application/json" \
  -H "X-User-Id: 2" \
  -d '{"title": "Buy milk"}'
# => {"id":1,"title":"Buy milk","done":false,"ownerId":2}

# Carol creates her own todo (ownerId=3)
curl -s -X POST http://localhost:3000/api/todos \
  -H "Content-Type: application/json" \
  -H "X-User-Id: 3" \
  -d '{"title": "Call dentist"}'
# => {"id":2,"title":"Call dentist","done":false,"ownerId":3}

# Bob sees only his own todos
curl -s http://localhost:3000/api/todos -H "X-User-Id: 2"
# => [{"id":1,"title":"Buy milk","done":false,"ownerId":2}]

# Alice (admin) sees all todos
curl -s http://localhost:3000/api/todos -H "X-User-Id: 1"
# => [{"id":1,...},{"id":2,...}]

# Bob tries to delete Carol's todo — gets 403
curl -s -X DELETE http://localhost:3000/api/todos/2 -H "X-User-Id: 2"
# => {"error":"Forbidden"}

# Alice (admin) can delete Carol's todo
curl -s -X DELETE http://localhost:3000/api/todos/2 -H "X-User-Id: 1"
# => 204 No Content
```
