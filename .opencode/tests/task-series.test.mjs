import assert from "node:assert/strict"
import { test } from "node:test"

import { TaskSeriesPlugin } from "../plugins/task-series.js"

test("Task-Series plugin exposes one single-series tool and one pool tool", async () => {
  const plugin = await TaskSeriesPlugin({ client: {} })
  assert.deepEqual(Object.keys(plugin.tool).sort(), ["task_series", "task_series_pool"])
  assert.match(plugin.tool.task_series.description, /one complete Task-Series/i)
  assert.match(plugin.tool.task_series_pool.description, /independent Task-Series/i)
})

test("Task-Series tools expose the required schemas", async () => {
  const plugin = await TaskSeriesPlugin({ client: {} })
  assert.equal(typeof plugin.tool.task_series.args.phase, "object")
  assert.equal(typeof plugin.tool.task_series.args.task_file, "object")
  assert.equal(typeof plugin.tool.task_series_pool.args.series, "object")
  assert.equal(typeof plugin.tool.task_series_pool.args.lane_order, "object")
})
