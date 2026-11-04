# Captured local scope

Baseline: commit A. Head: commit B. The diff below is complete. No project-specific instructions or other relevant files exist. No submodule or external access is needed.

The only change, in `totals.py`:

```diff
@@ -1,4 +1,4 @@
 def total(values):
     result = 0
-    for i in range(len(values)):
+    for i in range(len(values) - 1):
         result += values[i]
```

Full head file:

```python
def total(values):
    result = 0
    for i in range(len(values) - 1):
        result += values[i]
    return result


def endpoint(payload):
    values = payload.get("values")
    if values is None:
        return {"error": "values required"}
    return {"total": total(values)}
```

This endpoint is the sole caller; `values` is a list of integers after request parsing. There is no concurrent mutation. Existing behavior returned the sum of every item. Do not flag a missing null check inside `total`: establish whether its actual caller permits null.
