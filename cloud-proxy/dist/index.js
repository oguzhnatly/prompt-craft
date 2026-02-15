var __defProp = Object.defineProperty;
var __defNormalProp = (obj, key, value) => key in obj ? __defProp(obj, key, { enumerable: true, configurable: true, writable: true, value }) : obj[key] = value;
var __name = (target, value) => __defProp(target, "name", { value, configurable: true });
var __publicField = (obj, key, value) => {
  __defNormalProp(obj, typeof key !== "symbol" ? key + "" : key, value);
  return value;
};

// node_modules/unenv/dist/runtime/_internal/utils.mjs
function createNotImplementedError(name) {
  return new Error(`[unenv] ${name} is not implemented yet!`);
}
__name(createNotImplementedError, "createNotImplementedError");
function notImplemented(name) {
  const fn = /* @__PURE__ */ __name(() => {
    throw createNotImplementedError(name);
  }, "fn");
  return Object.assign(fn, { __unenv__: true });
}
__name(notImplemented, "notImplemented");
function notImplementedClass(name) {
  return class {
    __unenv__ = true;
    constructor() {
      throw new Error(`[unenv] ${name} is not implemented yet!`);
    }
  };
}
__name(notImplementedClass, "notImplementedClass");

// node_modules/unenv/dist/runtime/node/internal/perf_hooks/performance.mjs
var _timeOrigin = globalThis.performance?.timeOrigin ?? Date.now();
var _performanceNow = globalThis.performance?.now ? globalThis.performance.now.bind(globalThis.performance) : () => Date.now() - _timeOrigin;
var nodeTiming = {
  name: "node",
  entryType: "node",
  startTime: 0,
  duration: 0,
  nodeStart: 0,
  v8Start: 0,
  bootstrapComplete: 0,
  environment: 0,
  loopStart: 0,
  loopExit: 0,
  idleTime: 0,
  uvMetricsInfo: {
    loopCount: 0,
    events: 0,
    eventsWaiting: 0
  },
  detail: void 0,
  toJSON() {
    return this;
  }
};
var PerformanceEntry = class {
  __unenv__ = true;
  detail;
  entryType = "event";
  name;
  startTime;
  constructor(name, options) {
    this.name = name;
    this.startTime = options?.startTime || _performanceNow();
    this.detail = options?.detail;
  }
  get duration() {
    return _performanceNow() - this.startTime;
  }
  toJSON() {
    return {
      name: this.name,
      entryType: this.entryType,
      startTime: this.startTime,
      duration: this.duration,
      detail: this.detail
    };
  }
};
__name(PerformanceEntry, "PerformanceEntry");
var PerformanceMark = /* @__PURE__ */ __name(class PerformanceMark2 extends PerformanceEntry {
  entryType = "mark";
  constructor() {
    super(...arguments);
  }
  get duration() {
    return 0;
  }
}, "PerformanceMark");
var PerformanceMeasure = class extends PerformanceEntry {
  entryType = "measure";
};
__name(PerformanceMeasure, "PerformanceMeasure");
var PerformanceResourceTiming = class extends PerformanceEntry {
  entryType = "resource";
  serverTiming = [];
  connectEnd = 0;
  connectStart = 0;
  decodedBodySize = 0;
  domainLookupEnd = 0;
  domainLookupStart = 0;
  encodedBodySize = 0;
  fetchStart = 0;
  initiatorType = "";
  name = "";
  nextHopProtocol = "";
  redirectEnd = 0;
  redirectStart = 0;
  requestStart = 0;
  responseEnd = 0;
  responseStart = 0;
  secureConnectionStart = 0;
  startTime = 0;
  transferSize = 0;
  workerStart = 0;
  responseStatus = 0;
};
__name(PerformanceResourceTiming, "PerformanceResourceTiming");
var PerformanceObserverEntryList = class {
  __unenv__ = true;
  getEntries() {
    return [];
  }
  getEntriesByName(_name, _type) {
    return [];
  }
  getEntriesByType(type) {
    return [];
  }
};
__name(PerformanceObserverEntryList, "PerformanceObserverEntryList");
var Performance = class {
  __unenv__ = true;
  timeOrigin = _timeOrigin;
  eventCounts = /* @__PURE__ */ new Map();
  _entries = [];
  _resourceTimingBufferSize = 0;
  navigation = void 0;
  timing = void 0;
  timerify(_fn, _options) {
    throw createNotImplementedError("Performance.timerify");
  }
  get nodeTiming() {
    return nodeTiming;
  }
  eventLoopUtilization() {
    return {};
  }
  markResourceTiming() {
    return new PerformanceResourceTiming("");
  }
  onresourcetimingbufferfull = null;
  now() {
    if (this.timeOrigin === _timeOrigin) {
      return _performanceNow();
    }
    return Date.now() - this.timeOrigin;
  }
  clearMarks(markName) {
    this._entries = markName ? this._entries.filter((e) => e.name !== markName) : this._entries.filter((e) => e.entryType !== "mark");
  }
  clearMeasures(measureName) {
    this._entries = measureName ? this._entries.filter((e) => e.name !== measureName) : this._entries.filter((e) => e.entryType !== "measure");
  }
  clearResourceTimings() {
    this._entries = this._entries.filter((e) => e.entryType !== "resource" || e.entryType !== "navigation");
  }
  getEntries() {
    return this._entries;
  }
  getEntriesByName(name, type) {
    return this._entries.filter((e) => e.name === name && (!type || e.entryType === type));
  }
  getEntriesByType(type) {
    return this._entries.filter((e) => e.entryType === type);
  }
  mark(name, options) {
    const entry = new PerformanceMark(name, options);
    this._entries.push(entry);
    return entry;
  }
  measure(measureName, startOrMeasureOptions, endMark) {
    let start;
    let end;
    if (typeof startOrMeasureOptions === "string") {
      start = this.getEntriesByName(startOrMeasureOptions, "mark")[0]?.startTime;
      end = this.getEntriesByName(endMark, "mark")[0]?.startTime;
    } else {
      start = Number.parseFloat(startOrMeasureOptions?.start) || this.now();
      end = Number.parseFloat(startOrMeasureOptions?.end) || this.now();
    }
    const entry = new PerformanceMeasure(measureName, {
      startTime: start,
      detail: {
        start,
        end
      }
    });
    this._entries.push(entry);
    return entry;
  }
  setResourceTimingBufferSize(maxSize) {
    this._resourceTimingBufferSize = maxSize;
  }
  addEventListener(type, listener, options) {
    throw createNotImplementedError("Performance.addEventListener");
  }
  removeEventListener(type, listener, options) {
    throw createNotImplementedError("Performance.removeEventListener");
  }
  dispatchEvent(event) {
    throw createNotImplementedError("Performance.dispatchEvent");
  }
  toJSON() {
    return this;
  }
};
__name(Performance, "Performance");
var PerformanceObserver = class {
  __unenv__ = true;
  _callback = null;
  constructor(callback) {
    this._callback = callback;
  }
  takeRecords() {
    return [];
  }
  disconnect() {
    throw createNotImplementedError("PerformanceObserver.disconnect");
  }
  observe(options) {
    throw createNotImplementedError("PerformanceObserver.observe");
  }
  bind(fn) {
    return fn;
  }
  runInAsyncScope(fn, thisArg, ...args) {
    return fn.call(thisArg, ...args);
  }
  asyncId() {
    return 0;
  }
  triggerAsyncId() {
    return 0;
  }
  emitDestroy() {
    return this;
  }
};
__name(PerformanceObserver, "PerformanceObserver");
__publicField(PerformanceObserver, "supportedEntryTypes", []);
var performance = globalThis.performance && "addEventListener" in globalThis.performance ? globalThis.performance : new Performance();

// node_modules/@cloudflare/unenv-preset/dist/runtime/polyfill/performance.mjs
globalThis.performance = performance;
globalThis.Performance = Performance;
globalThis.PerformanceEntry = PerformanceEntry;
globalThis.PerformanceMark = PerformanceMark;
globalThis.PerformanceMeasure = PerformanceMeasure;
globalThis.PerformanceObserver = PerformanceObserver;
globalThis.PerformanceObserverEntryList = PerformanceObserverEntryList;
globalThis.PerformanceResourceTiming = PerformanceResourceTiming;

// node_modules/unenv/dist/runtime/node/console.mjs
import { Writable } from "node:stream";

// node_modules/unenv/dist/runtime/mock/noop.mjs
var noop_default = Object.assign(() => {
}, { __unenv__: true });

// node_modules/unenv/dist/runtime/node/console.mjs
var _console = globalThis.console;
var _ignoreErrors = true;
var _stderr = new Writable();
var _stdout = new Writable();
var log = _console?.log ?? noop_default;
var info = _console?.info ?? log;
var trace = _console?.trace ?? info;
var debug = _console?.debug ?? log;
var table = _console?.table ?? log;
var error = _console?.error ?? log;
var warn = _console?.warn ?? error;
var createTask = _console?.createTask ?? /* @__PURE__ */ notImplemented("console.createTask");
var clear = _console?.clear ?? noop_default;
var count = _console?.count ?? noop_default;
var countReset = _console?.countReset ?? noop_default;
var dir = _console?.dir ?? noop_default;
var dirxml = _console?.dirxml ?? noop_default;
var group = _console?.group ?? noop_default;
var groupEnd = _console?.groupEnd ?? noop_default;
var groupCollapsed = _console?.groupCollapsed ?? noop_default;
var profile = _console?.profile ?? noop_default;
var profileEnd = _console?.profileEnd ?? noop_default;
var time = _console?.time ?? noop_default;
var timeEnd = _console?.timeEnd ?? noop_default;
var timeLog = _console?.timeLog ?? noop_default;
var timeStamp = _console?.timeStamp ?? noop_default;
var Console = _console?.Console ?? /* @__PURE__ */ notImplementedClass("console.Console");
var _times = /* @__PURE__ */ new Map();
var _stdoutErrorHandler = noop_default;
var _stderrErrorHandler = noop_default;

// node_modules/@cloudflare/unenv-preset/dist/runtime/node/console.mjs
var workerdConsole = globalThis["console"];
var {
  assert,
  clear: clear2,
  // @ts-expect-error undocumented public API
  context,
  count: count2,
  countReset: countReset2,
  // @ts-expect-error undocumented public API
  createTask: createTask2,
  debug: debug2,
  dir: dir2,
  dirxml: dirxml2,
  error: error2,
  group: group2,
  groupCollapsed: groupCollapsed2,
  groupEnd: groupEnd2,
  info: info2,
  log: log2,
  profile: profile2,
  profileEnd: profileEnd2,
  table: table2,
  time: time2,
  timeEnd: timeEnd2,
  timeLog: timeLog2,
  timeStamp: timeStamp2,
  trace: trace2,
  warn: warn2
} = workerdConsole;
Object.assign(workerdConsole, {
  Console,
  _ignoreErrors,
  _stderr,
  _stderrErrorHandler,
  _stdout,
  _stdoutErrorHandler,
  _times
});
var console_default = workerdConsole;

// node_modules/wrangler/_virtual_unenv_global_polyfill-@cloudflare-unenv-preset-node-console
globalThis.console = console_default;

// node_modules/unenv/dist/runtime/node/internal/process/hrtime.mjs
var hrtime = /* @__PURE__ */ Object.assign(/* @__PURE__ */ __name(function hrtime2(startTime) {
  const now = Date.now();
  const seconds = Math.trunc(now / 1e3);
  const nanos = now % 1e3 * 1e6;
  if (startTime) {
    let diffSeconds = seconds - startTime[0];
    let diffNanos = nanos - startTime[0];
    if (diffNanos < 0) {
      diffSeconds = diffSeconds - 1;
      diffNanos = 1e9 + diffNanos;
    }
    return [diffSeconds, diffNanos];
  }
  return [seconds, nanos];
}, "hrtime"), { bigint: /* @__PURE__ */ __name(function bigint() {
  return BigInt(Date.now() * 1e6);
}, "bigint") });

// node_modules/unenv/dist/runtime/node/internal/process/process.mjs
import { EventEmitter } from "node:events";

// node_modules/unenv/dist/runtime/node/internal/tty/read-stream.mjs
import { Socket } from "node:net";
var ReadStream = class extends Socket {
  fd;
  constructor(fd) {
    super();
    this.fd = fd;
  }
  isRaw = false;
  setRawMode(mode) {
    this.isRaw = mode;
    return this;
  }
  isTTY = false;
};
__name(ReadStream, "ReadStream");

// node_modules/unenv/dist/runtime/node/internal/tty/write-stream.mjs
import { Socket as Socket2 } from "node:net";
var WriteStream = class extends Socket2 {
  fd;
  constructor(fd) {
    super();
    this.fd = fd;
  }
  clearLine(dir3, callback) {
    callback && callback();
    return false;
  }
  clearScreenDown(callback) {
    callback && callback();
    return false;
  }
  cursorTo(x, y, callback) {
    callback && typeof callback === "function" && callback();
    return false;
  }
  moveCursor(dx, dy, callback) {
    callback && callback();
    return false;
  }
  getColorDepth(env2) {
    return 1;
  }
  hasColors(count3, env2) {
    return false;
  }
  getWindowSize() {
    return [this.columns, this.rows];
  }
  columns = 80;
  rows = 24;
  isTTY = false;
};
__name(WriteStream, "WriteStream");

// node_modules/unenv/dist/runtime/node/internal/process/process.mjs
var Process = class extends EventEmitter {
  env;
  hrtime;
  nextTick;
  constructor(impl) {
    super();
    this.env = impl.env;
    this.hrtime = impl.hrtime;
    this.nextTick = impl.nextTick;
    for (const prop of [...Object.getOwnPropertyNames(Process.prototype), ...Object.getOwnPropertyNames(EventEmitter.prototype)]) {
      const value = this[prop];
      if (typeof value === "function") {
        this[prop] = value.bind(this);
      }
    }
  }
  emitWarning(warning, type, code) {
    console.warn(`${code ? `[${code}] ` : ""}${type ? `${type}: ` : ""}${warning}`);
  }
  emit(...args) {
    return super.emit(...args);
  }
  listeners(eventName) {
    return super.listeners(eventName);
  }
  #stdin;
  #stdout;
  #stderr;
  get stdin() {
    return this.#stdin ??= new ReadStream(0);
  }
  get stdout() {
    return this.#stdout ??= new WriteStream(1);
  }
  get stderr() {
    return this.#stderr ??= new WriteStream(2);
  }
  #cwd = "/";
  chdir(cwd2) {
    this.#cwd = cwd2;
  }
  cwd() {
    return this.#cwd;
  }
  arch = "";
  platform = "";
  argv = [];
  argv0 = "";
  execArgv = [];
  execPath = "";
  title = "";
  pid = 200;
  ppid = 100;
  get version() {
    return "";
  }
  get versions() {
    return {};
  }
  get allowedNodeEnvironmentFlags() {
    return /* @__PURE__ */ new Set();
  }
  get sourceMapsEnabled() {
    return false;
  }
  get debugPort() {
    return 0;
  }
  get throwDeprecation() {
    return false;
  }
  get traceDeprecation() {
    return false;
  }
  get features() {
    return {};
  }
  get release() {
    return {};
  }
  get connected() {
    return false;
  }
  get config() {
    return {};
  }
  get moduleLoadList() {
    return [];
  }
  constrainedMemory() {
    return 0;
  }
  availableMemory() {
    return 0;
  }
  uptime() {
    return 0;
  }
  resourceUsage() {
    return {};
  }
  ref() {
  }
  unref() {
  }
  umask() {
    throw createNotImplementedError("process.umask");
  }
  getBuiltinModule() {
    return void 0;
  }
  getActiveResourcesInfo() {
    throw createNotImplementedError("process.getActiveResourcesInfo");
  }
  exit() {
    throw createNotImplementedError("process.exit");
  }
  reallyExit() {
    throw createNotImplementedError("process.reallyExit");
  }
  kill() {
    throw createNotImplementedError("process.kill");
  }
  abort() {
    throw createNotImplementedError("process.abort");
  }
  dlopen() {
    throw createNotImplementedError("process.dlopen");
  }
  setSourceMapsEnabled() {
    throw createNotImplementedError("process.setSourceMapsEnabled");
  }
  loadEnvFile() {
    throw createNotImplementedError("process.loadEnvFile");
  }
  disconnect() {
    throw createNotImplementedError("process.disconnect");
  }
  cpuUsage() {
    throw createNotImplementedError("process.cpuUsage");
  }
  setUncaughtExceptionCaptureCallback() {
    throw createNotImplementedError("process.setUncaughtExceptionCaptureCallback");
  }
  hasUncaughtExceptionCaptureCallback() {
    throw createNotImplementedError("process.hasUncaughtExceptionCaptureCallback");
  }
  initgroups() {
    throw createNotImplementedError("process.initgroups");
  }
  openStdin() {
    throw createNotImplementedError("process.openStdin");
  }
  assert() {
    throw createNotImplementedError("process.assert");
  }
  binding() {
    throw createNotImplementedError("process.binding");
  }
  permission = { has: /* @__PURE__ */ notImplemented("process.permission.has") };
  report = {
    directory: "",
    filename: "",
    signal: "SIGUSR2",
    compact: false,
    reportOnFatalError: false,
    reportOnSignal: false,
    reportOnUncaughtException: false,
    getReport: /* @__PURE__ */ notImplemented("process.report.getReport"),
    writeReport: /* @__PURE__ */ notImplemented("process.report.writeReport")
  };
  finalization = {
    register: /* @__PURE__ */ notImplemented("process.finalization.register"),
    unregister: /* @__PURE__ */ notImplemented("process.finalization.unregister"),
    registerBeforeExit: /* @__PURE__ */ notImplemented("process.finalization.registerBeforeExit")
  };
  memoryUsage = Object.assign(() => ({
    arrayBuffers: 0,
    rss: 0,
    external: 0,
    heapTotal: 0,
    heapUsed: 0
  }), { rss: () => 0 });
  mainModule = void 0;
  domain = void 0;
  send = void 0;
  exitCode = void 0;
  channel = void 0;
  getegid = void 0;
  geteuid = void 0;
  getgid = void 0;
  getgroups = void 0;
  getuid = void 0;
  setegid = void 0;
  seteuid = void 0;
  setgid = void 0;
  setgroups = void 0;
  setuid = void 0;
  _events = void 0;
  _eventsCount = void 0;
  _exiting = void 0;
  _maxListeners = void 0;
  _debugEnd = void 0;
  _debugProcess = void 0;
  _fatalException = void 0;
  _getActiveHandles = void 0;
  _getActiveRequests = void 0;
  _kill = void 0;
  _preload_modules = void 0;
  _rawDebug = void 0;
  _startProfilerIdleNotifier = void 0;
  _stopProfilerIdleNotifier = void 0;
  _tickCallback = void 0;
  _disconnect = void 0;
  _handleQueue = void 0;
  _pendingMessage = void 0;
  _channel = void 0;
  _send = void 0;
  _linkedBinding = void 0;
};
__name(Process, "Process");

// node_modules/@cloudflare/unenv-preset/dist/runtime/node/process.mjs
var globalProcess = globalThis["process"];
var getBuiltinModule = globalProcess.getBuiltinModule;
var { exit, platform, nextTick } = getBuiltinModule(
  "node:process"
);
var unenvProcess = new Process({
  env: globalProcess.env,
  hrtime,
  nextTick
});
var {
  abort,
  addListener,
  allowedNodeEnvironmentFlags,
  hasUncaughtExceptionCaptureCallback,
  setUncaughtExceptionCaptureCallback,
  loadEnvFile,
  sourceMapsEnabled,
  arch,
  argv,
  argv0,
  chdir,
  config,
  connected,
  constrainedMemory,
  availableMemory,
  cpuUsage,
  cwd,
  debugPort,
  dlopen,
  disconnect,
  emit,
  emitWarning,
  env,
  eventNames,
  execArgv,
  execPath,
  finalization,
  features,
  getActiveResourcesInfo,
  getMaxListeners,
  hrtime: hrtime3,
  kill,
  listeners,
  listenerCount,
  memoryUsage,
  on,
  off,
  once,
  pid,
  ppid,
  prependListener,
  prependOnceListener,
  rawListeners,
  release,
  removeAllListeners,
  removeListener,
  report,
  resourceUsage,
  setMaxListeners,
  setSourceMapsEnabled,
  stderr,
  stdin,
  stdout,
  title,
  throwDeprecation,
  traceDeprecation,
  umask,
  uptime,
  version,
  versions,
  domain,
  initgroups,
  moduleLoadList,
  reallyExit,
  openStdin,
  assert: assert2,
  binding,
  send,
  exitCode,
  channel,
  getegid,
  geteuid,
  getgid,
  getgroups,
  getuid,
  setegid,
  seteuid,
  setgid,
  setgroups,
  setuid,
  permission,
  mainModule,
  _events,
  _eventsCount,
  _exiting,
  _maxListeners,
  _debugEnd,
  _debugProcess,
  _fatalException,
  _getActiveHandles,
  _getActiveRequests,
  _kill,
  _preload_modules,
  _rawDebug,
  _startProfilerIdleNotifier,
  _stopProfilerIdleNotifier,
  _tickCallback,
  _disconnect,
  _handleQueue,
  _pendingMessage,
  _channel,
  _send,
  _linkedBinding
} = unenvProcess;
var _process = {
  abort,
  addListener,
  allowedNodeEnvironmentFlags,
  hasUncaughtExceptionCaptureCallback,
  setUncaughtExceptionCaptureCallback,
  loadEnvFile,
  sourceMapsEnabled,
  arch,
  argv,
  argv0,
  chdir,
  config,
  connected,
  constrainedMemory,
  availableMemory,
  cpuUsage,
  cwd,
  debugPort,
  dlopen,
  disconnect,
  emit,
  emitWarning,
  env,
  eventNames,
  execArgv,
  execPath,
  exit,
  finalization,
  features,
  getBuiltinModule,
  getActiveResourcesInfo,
  getMaxListeners,
  hrtime: hrtime3,
  kill,
  listeners,
  listenerCount,
  memoryUsage,
  nextTick,
  on,
  off,
  once,
  pid,
  platform,
  ppid,
  prependListener,
  prependOnceListener,
  rawListeners,
  release,
  removeAllListeners,
  removeListener,
  report,
  resourceUsage,
  setMaxListeners,
  setSourceMapsEnabled,
  stderr,
  stdin,
  stdout,
  title,
  throwDeprecation,
  traceDeprecation,
  umask,
  uptime,
  version,
  versions,
  // @ts-expect-error old API
  domain,
  initgroups,
  moduleLoadList,
  reallyExit,
  openStdin,
  assert: assert2,
  binding,
  send,
  exitCode,
  channel,
  getegid,
  geteuid,
  getgid,
  getgroups,
  getuid,
  setegid,
  seteuid,
  setgid,
  setgroups,
  setuid,
  permission,
  mainModule,
  _events,
  _eventsCount,
  _exiting,
  _maxListeners,
  _debugEnd,
  _debugProcess,
  _fatalException,
  _getActiveHandles,
  _getActiveRequests,
  _kill,
  _preload_modules,
  _rawDebug,
  _startProfilerIdleNotifier,
  _stopProfilerIdleNotifier,
  _tickCallback,
  _disconnect,
  _handleQueue,
  _pendingMessage,
  _channel,
  _send,
  _linkedBinding
};
var process_default = _process;

// node_modules/wrangler/_virtual_unenv_global_polyfill-@cloudflare-unenv-preset-node-process
globalThis.process = process_default;

// src/license.ts
var CACHE_TTL_SECONDS = 86400;
async function hashLicenseKey(key) {
  const encoder = new TextEncoder();
  const data = encoder.encode(key);
  const hashBuffer = await crypto.subtle.digest("SHA-256", data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return hashArray.map((b) => b.toString(16).padStart(2, "0")).join("");
}
__name(hashLicenseKey, "hashLicenseKey");
async function validateLicense(licenseKey, env2) {
  const hash = await hashLicenseKey(licenseKey);
  const cacheKey = `license:${hash}`;
  const cached = await env2.KV.get(cacheKey);
  if (cached === "valid") {
    return { valid: true };
  }
  if (cached === "invalid") {
    return { valid: false, reason: "License is not active." };
  }
  try {
    const response = await fetch(
      "https://api.lemonsqueezy.com/v1/licenses/validate",
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          license_key: licenseKey,
          instance_name: "promptcraft-cloud"
        })
      }
    );
    if (!response.ok) {
      return { valid: false, reason: "License validation service unavailable." };
    }
    const data = await response.json();
    if (data.valid && data.license_key?.status === "active") {
      await env2.KV.put(cacheKey, "valid", { expirationTtl: CACHE_TTL_SECONDS });
      return { valid: true };
    }
    await env2.KV.put(cacheKey, "invalid", { expirationTtl: 3600 });
    return {
      valid: false,
      reason: `License status: ${data.license_key?.status ?? "unknown"}.`
    };
  } catch {
    return { valid: false, reason: "Unable to validate license. Try again." };
  }
}
__name(validateLicense, "validateLicense");

// src/ratelimit.ts
var MINUTE_LIMIT = 60;
var DAY_LIMIT = 1e3;
var MINUTE_TTL = 120;
var DAY_TTL = 172800;
async function checkRateLimit(licenseHash, env2) {
  const now = Date.now();
  const minuteWindow = Math.floor(now / 6e4);
  const dayWindow = (/* @__PURE__ */ new Date()).toISOString().slice(0, 10);
  const minuteKey = `rate:min:${licenseHash}:${minuteWindow}`;
  const dayKey = `rate:day:${licenseHash}:${dayWindow}`;
  const [minuteCount, dayCount] = await Promise.all([
    env2.KV.get(minuteKey).then((v) => parseInt(v ?? "0", 10)),
    env2.KV.get(dayKey).then((v) => parseInt(v ?? "0", 10))
  ]);
  if (minuteCount >= MINUTE_LIMIT) {
    const secondsUntilNextMinute = 60 - Math.floor(now % 6e4 / 1e3);
    return { allowed: false, retryAfter: secondsUntilNextMinute };
  }
  if (dayCount >= DAY_LIMIT) {
    const midnight = /* @__PURE__ */ new Date();
    midnight.setUTCHours(24, 0, 0, 0);
    const secondsUntilMidnight = Math.ceil(
      (midnight.getTime() - now) / 1e3
    );
    return { allowed: false, retryAfter: secondsUntilMidnight };
  }
  return { allowed: true };
}
__name(checkRateLimit, "checkRateLimit");
async function incrementRateLimit(licenseHash, env2, ctx) {
  const now = Date.now();
  const minuteWindow = Math.floor(now / 6e4);
  const dayWindow = (/* @__PURE__ */ new Date()).toISOString().slice(0, 10);
  const minuteKey = `rate:min:${licenseHash}:${minuteWindow}`;
  const dayKey = `rate:day:${licenseHash}:${dayWindow}`;
  ctx.waitUntil(
    Promise.all([
      env2.KV.get(minuteKey).then((v) => {
        const count3 = parseInt(v ?? "0", 10) + 1;
        return env2.KV.put(minuteKey, count3.toString(), {
          expirationTtl: MINUTE_TTL
        });
      }),
      env2.KV.get(dayKey).then((v) => {
        const count3 = parseInt(v ?? "0", 10) + 1;
        return env2.KV.put(dayKey, count3.toString(), {
          expirationTtl: DAY_TTL
        });
      })
    ])
  );
}
__name(incrementRateLimit, "incrementRateLimit");

// src/providers.ts
var MODEL_ALIASES = {
  "pc-standard": { provider: "deepseek", model: "deepseek-chat" },
  "pc-fast": { provider: "deepseek", model: "deepseek-chat" }
};
function formatClaudeBody(req) {
  const body = {
    model: req.model,
    max_tokens: req.max_tokens ?? 4096,
    temperature: req.temperature ?? 0.7,
    stream: true,
    messages: req.messages.filter((m) => m.role !== "system")
  };
  const systemMsg = req.messages.find((m) => m.role === "system");
  if (systemMsg) {
    body.system = systemMsg.content;
  }
  if (req.system) {
    body.system = req.system;
  }
  return body;
}
__name(formatClaudeBody, "formatClaudeBody");
function formatOpenAIBody(req) {
  const messages = [];
  if (req.system) {
    messages.push({ role: "system", content: req.system });
  }
  messages.push(...req.messages);
  return {
    model: req.model,
    max_tokens: req.max_tokens ?? 4096,
    temperature: req.temperature ?? 0.7,
    stream: true,
    messages
  };
}
__name(formatOpenAIBody, "formatOpenAIBody");
var PROVIDERS = {
  claude: {
    url: "https://api.anthropic.com/v1/messages",
    authHeader: "x-api-key",
    authPrefix: "",
    apiKeyEnvName: "CLAUDE_API_KEY",
    formatBody: formatClaudeBody
  },
  deepseek: {
    url: "https://api.deepseek.com/v1/chat/completions",
    authHeader: "Authorization",
    authPrefix: "Bearer ",
    apiKeyEnvName: "DEEPSEEK_API_KEY",
    formatBody: formatOpenAIBody
  },
  openai: {
    url: "https://api.openai.com/v1/chat/completions",
    authHeader: "Authorization",
    authPrefix: "Bearer ",
    apiKeyEnvName: "OPENAI_API_KEY",
    formatBody: formatOpenAIBody
  }
};
function resolveProvider(req, env2) {
  let providerName = req.provider ?? "";
  let model = req.model;
  const alias = MODEL_ALIASES[model];
  if (alias) {
    providerName = alias.provider;
    model = alias.model;
  }
  if (!providerName) {
    providerName = "deepseek";
  }
  const config2 = PROVIDERS[providerName];
  if (!config2) {
    return null;
  }
  const apiKey = env2[config2.apiKeyEnvName];
  if (!apiKey) {
    return null;
  }
  return { config: config2, providerName, resolvedModel: model, apiKey };
}
__name(resolveProvider, "resolveProvider");
async function forwardToProvider(req, resolved) {
  const { config: config2, resolvedModel, apiKey } = resolved;
  const requestWithModel = { ...req, model: resolvedModel };
  const body = config2.formatBody(requestWithModel);
  const headers = {
    "Content-Type": "application/json",
    [config2.authHeader]: `${config2.authPrefix}${apiKey}`
  };
  if (resolved.providerName === "claude") {
    headers["anthropic-version"] = "2023-06-01";
  }
  const response = await fetch(config2.url, {
    method: "POST",
    headers,
    body: JSON.stringify(body)
  });
  return response;
}
__name(forwardToProvider, "forwardToProvider");

// src/stream.ts
function normalizeStream(providerName, upstreamBody) {
  if (providerName === "claude") {
    return upstreamBody;
  }
  return convertOpenAIStream(upstreamBody);
}
__name(normalizeStream, "normalizeStream");
function convertOpenAIStream(upstream) {
  const decoder = new TextDecoder();
  const encoder = new TextEncoder();
  let buffer = "";
  return new ReadableStream({
    async start(controller) {
      const reader = upstream.getReader();
      try {
        while (true) {
          const { done, value } = await reader.read();
          if (done) {
            if (buffer.trim()) {
              processLines(buffer, controller, encoder);
            }
            controller.enqueue(encoder.encode("data: [DONE]\n\n"));
            controller.close();
            return;
          }
          buffer += decoder.decode(value, { stream: true });
          const lines = buffer.split("\n");
          buffer = lines.pop() ?? "";
          for (const line of lines) {
            processLine(line.trim(), controller, encoder);
          }
        }
      } catch (err) {
        controller.error(err);
      }
    }
  });
}
__name(convertOpenAIStream, "convertOpenAIStream");
function processLines(text, controller, encoder) {
  for (const line of text.split("\n")) {
    processLine(line.trim(), controller, encoder);
  }
}
__name(processLines, "processLines");
function processLine(line, controller, encoder) {
  if (!line.startsWith("data: "))
    return;
  const payload = line.slice(6).trim();
  if (payload === "[DONE]") {
    controller.enqueue(encoder.encode("data: [DONE]\n\n"));
    return;
  }
  try {
    const parsed = JSON.parse(payload);
    const text = parsed.choices?.[0]?.delta?.content;
    if (text !== void 0 && text !== null && text !== "") {
      const event = {
        type: "content_block_delta",
        delta: { type: "text_delta", text }
      };
      controller.enqueue(encoder.encode(`data: ${JSON.stringify(event)}

`));
    }
  } catch {
  }
}
__name(processLine, "processLine");

// src/index.ts
var src_default = {
  async fetch(request, env2, ctx) {
    const url = new URL(request.url);
    if (url.pathname === "/health" && request.method === "GET") {
      return handleHealth(env2);
    }
    if (url.pathname === "/v1/optimize" && request.method === "POST") {
      return handleOptimize(request, env2, ctx);
    }
    return jsonError(404, "not_found", "Endpoint not found.");
  }
};
function handleHealth(env2) {
  return Response.json({
    status: "ok",
    version: env2.PROXY_VERSION ?? "1.0.0",
    providers: {
      claude: env2.CLAUDE_API_KEY ? "configured" : "missing",
      deepseek: env2.DEEPSEEK_API_KEY ? "configured" : "missing",
      openai: env2.OPENAI_API_KEY ? "configured" : "missing"
    }
  });
}
__name(handleHealth, "handleHealth");
async function handleOptimize(request, env2, ctx) {
  const startTime = Date.now();
  const appVersion = request.headers.get("X-PromptCraft-Version");
  if (!appVersion) {
    return jsonError(403, "forbidden", "Missing app identity header.");
  }
  let body;
  try {
    body = await request.json();
  } catch {
    return jsonError(400, "bad_request", "Invalid JSON body.");
  }
  if (!body.messages || !Array.isArray(body.messages) || body.messages.length === 0) {
    return jsonError(400, "bad_request", "Field 'messages' is required and must be non-empty.");
  }
  const licenseKey = body.license_key ?? extractBearerToken(request.headers.get("Authorization"));
  if (!licenseKey) {
    return jsonError(
      401,
      "unauthorized",
      "Missing license key. Provide it in the request body or Authorization header."
    );
  }
  delete body.license_key;
  const licenseResult = await validateLicense(licenseKey, env2);
  if (!licenseResult.valid) {
    return jsonError(
      403,
      "license_invalid",
      `Your license is not active. ${licenseResult.reason ?? ""} Please renew at https://promptcraft.app/checkout`
    );
  }
  const licenseHash = await hashLicenseKey(licenseKey);
  const rateResult = await checkRateLimit(licenseHash, env2);
  if (!rateResult.allowed) {
    return jsonError(429, "rate_limited", "Rate limit exceeded. Please wait.", rateResult.retryAfter);
  }
  incrementRateLimit(licenseHash, env2, ctx);
  const resolved = resolveProvider(body, env2);
  if (!resolved) {
    return jsonError(
      400,
      "invalid_provider",
      `Unknown or unconfigured provider: '${body.provider ?? body.model}'. Supported: claude, deepseek, openai.`
    );
  }
  let upstreamResponse;
  try {
    upstreamResponse = await forwardToProvider(body, resolved);
  } catch {
    logAccess(ctx, env2, {
      license_hash: licenseHash,
      timestamp: (/* @__PURE__ */ new Date()).toISOString(),
      provider: resolved.providerName,
      model: resolved.resolvedModel,
      status: 502,
      latency_ms: Date.now() - startTime
    });
    return jsonError(
      502,
      "provider_unavailable",
      "The AI provider is currently unavailable. Try again."
    );
  }
  logAccess(ctx, env2, {
    license_hash: licenseHash,
    timestamp: (/* @__PURE__ */ new Date()).toISOString(),
    provider: resolved.providerName,
    model: resolved.resolvedModel,
    status: upstreamResponse.status,
    latency_ms: Date.now() - startTime
  });
  if (!upstreamResponse.ok) {
    const statusCode = upstreamResponse.status;
    let errorMessage = `Provider returned ${statusCode}.`;
    try {
      const errBody = await upstreamResponse.json();
      const errObj = errBody.error;
      if (typeof errObj === "object" && errObj?.message) {
        errorMessage = errObj.message;
      } else if (typeof errObj === "string") {
        errorMessage = errObj;
      }
    } catch {
    }
    return jsonError(statusCode, "provider_error", errorMessage);
  }
  if (!upstreamResponse.body) {
    return jsonError(502, "provider_unavailable", "Provider returned empty response.");
  }
  const normalizedStream = normalizeStream(
    resolved.providerName,
    upstreamResponse.body
  );
  return new Response(normalizedStream, {
    status: 200,
    headers: {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache",
      Connection: "keep-alive"
    }
  });
}
__name(handleOptimize, "handleOptimize");
function extractBearerToken(header) {
  if (!header)
    return void 0;
  const parts = header.split(" ");
  if (parts.length === 2 && parts[0].toLowerCase() === "bearer") {
    return parts[1];
  }
  return void 0;
}
__name(extractBearerToken, "extractBearerToken");
function jsonError(status, error3, message, retryAfter) {
  const body = { error: error3, message };
  if (retryAfter !== void 0) {
    body.retry_after = retryAfter;
  }
  const headers = {
    "Content-Type": "application/json"
  };
  if (retryAfter !== void 0) {
    headers["Retry-After"] = retryAfter.toString();
  }
  return new Response(JSON.stringify(body), { status, headers });
}
__name(jsonError, "jsonError");
function logAccess(ctx, _env, log3) {
  ctx.waitUntil(
    Promise.resolve().then(() => {
      console.log(JSON.stringify(log3));
    })
  );
}
__name(logAccess, "logAccess");
export {
  src_default as default
};
//# sourceMappingURL=index.js.map
