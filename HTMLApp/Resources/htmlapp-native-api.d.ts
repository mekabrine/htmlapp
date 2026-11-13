// GENERATED from native-capability-definitions.json — do not edit manually.
export type HTMLAppNativeMethod =
  | 'ai.available'
  | 'ai.cancel'
  | 'ai.classify'
  | 'ai.complete'
  | 'ai.localAvailable'
  | 'ai.localComplete'
  | 'ai.stream'
  | 'appStorage.all'
  | 'appStorage.clear'
  | 'appStorage.get'
  | 'appStorage.remove'
  | 'appStorage.set'
  | 'audio.cancelRecording'
  | 'audio.levels'
  | 'audio.pause'
  | 'audio.play'
  | 'audio.record'
  | 'audio.stop'
  | 'audio.stopRecording'
  | 'backend.notify'
  | 'backend.read'
  | 'backend.request'
  | 'backend.status'
  | 'backend.subscribe'
  | 'backend.unsubscribe'
  | 'background.configure'
  | 'background.list'
  | 'background.refreshNow'
  | 'background.remove'
  | 'biometrics.authenticate'
  | 'bluetooth.battery'
  | 'bluetooth.gattRead'
  | 'bluetooth.gattStop'
  | 'bluetooth.gattSubscribe'
  | 'bluetooth.gattWrite'
  | 'bluetooth.scan'
  | 'bridge.cancel'
  | 'calendar.createEvent'
  | 'calendar.deleteEvent'
  | 'calendar.events'
  | 'calendar.updateEvent'
  | 'camera.captureFrame'
  | 'camera.capturePhoto'
  | 'camera.startFrames'
  | 'camera.stopFrames'
  | 'capabilities.describe'
  | 'capabilities.list'
  | 'clipboard.readText'
  | 'clipboard.writeText'
  | 'contacts.create'
  | 'contacts.list'
  | 'contacts.pick'
  | 'controls.acknowledge'
  | 'controls.configure'
  | 'controls.read'
  | 'controls.remove'
  | 'controls.set'
  | 'coreML.infer'
  | 'coreML.load'
  | 'coreML.unload'
  | 'db.count'
  | 'db.delete'
  | 'db.export'
  | 'db.get'
  | 'db.import'
  | 'db.put'
  | 'db.query'
  | 'db.search'
  | 'db.vectorSearch'
  | 'device.battery'
  | 'device.brightness'
  | 'device.info'
  | 'device.keepAwake'
  | 'device.torch'
  | 'documents.scan'
  | 'drawing.open'
  | 'externalApps.maps'
  | 'externalApps.shortcuts'
  | 'files.pick'
  | 'files.read'
  | 'gamepad.list'
  | 'gamepad.start'
  | 'gamepad.stop'
  | 'haptics.pattern'
  | 'haptics.play'
  | 'health.available'
  | 'health.range'
  | 'health.today'
  | 'image.filter'
  | 'language.detect'
  | 'language.entities'
  | 'language.sentiment'
  | 'language.tokenize'
  | 'liveActivities.end'
  | 'liveActivities.list'
  | 'liveActivities.perform'
  | 'liveActivities.start'
  | 'liveActivities.update'
  | 'location.backgroundDisable'
  | 'location.backgroundEnable'
  | 'location.backgroundRead'
  | 'location.backgroundStatus'
  | 'location.distance'
  | 'location.geocode'
  | 'location.reverseGeocode'
  | 'location.roadSpeedLimit'
  | 'map.embed'
  | 'map.hide'
  | 'map.show'
  | 'midi.destinations'
  | 'midi.send'
  | 'motion.altitude'
  | 'motion.pedometer'
  | 'motion.start'
  | 'motion.stop'
  | 'music.loadBank'
  | 'music.noteOff'
  | 'music.noteOn'
  | 'music.stop'
  | 'network.allowedDomains'
  | 'network.request'
  | 'network.revokeDomain'
  | 'network.status'
  | 'nfc.available'
  | 'nfc.readNDEF'
  | 'nfc.writeText'
  | 'notifications.cancel'
  | 'notifications.installSound'
  | 'notifications.schedule'
  | 'pdf.inspect'
  | 'permissions.openSettings'
  | 'permissions.request'
  | 'permissions.status'
  | 'photos.pick'
  | 'photos.read'
  | 'photos.save'
  | 'push.register'
  | 'reminders.create'
  | 'reminders.delete'
  | 'reminders.list'
  | 'reminders.update'
  | 'scene.hide'
  | 'scene.show'
  | 'secureStorage.get'
  | 'secureStorage.remove'
  | 'secureStorage.set'
  | 'share.present'
  | 'shortcuts.consumeAction'
  | 'speech.listen'
  | 'speech.listenStop'
  | 'speech.recognize'
  | 'speech.speak'
  | 'speech.stop'
  | 'speech.stopRecognizing'
  | 'spotlight.clear'
  | 'spotlight.enable'
  | 'spotlight.index'
  | 'spotlight.remove'
  | 'symbols.render'
  | 'symbols.search'
  | 'system.open'
  | 'tabs.configure'
  | 'tabs.pulse'
  | 'tabs.remove'
  | 'tabs.select'
  | 'tabs.setHidden'
  | 'tabs.update'
  | 'ui.alert'
  | 'ui.colorPicker'
  | 'ui.controls'
  | 'ui.datePicker'
  | 'ui.glassHide'
  | 'ui.glassShow'
  | 'ui.list'
  | 'ui.listDismiss'
  | 'ui.listUpdate'
  | 'ui.menu'
  | 'video.capture'
  | 'vision.classifyImage'
  | 'vision.detectFaces'
  | 'vision.recognizeText'
  | 'vision.scanCodes'
  | 'widgets.configure'
  | 'widgets.list'
  | 'widgets.reload'
  | 'widgets.remove';
export interface HTMLAppNativeFrame { x: number; y: number; width: number; height: number }
export interface HTMLAppXYZ { x: number; y: number; z: number }

export interface HTMLAppNativeCapabilitySnapshot {
  protocolVersion: number;
  descriptorVersion: number;
  methods: HTMLAppNativeMethod[];
  permissions: string[];
  torchAvailable?: boolean;
  liveActivitiesAvailable?: boolean;
  controlCenterAvailable?: boolean;
  widgetCustomization?: { schemaVersion: number; elementTypes: string[]; timeFormats: HTMLAppWidgetTimeFormat[]; liveSelectedTimeUnits: boolean; maxElements: number; maxDepth: number; };
}

export interface HTMLAppNativeCapabilityDescriptor {
  method: HTMLAppNativeMethod;
  protocolVersion: number;
  available: boolean;
  implemented?: boolean;
  hostPolicy?: string;
  availabilityNote?: string;
  permission: string;
  title: string;
  description: string;
  usage: string;
  constraints: string;
  minimumIOS: string;
  cancellable: boolean;
  userInitiationRecommended: boolean;
  argumentTypes: Record<string, "string" | "number" | "boolean" | "object" | "array">;
  requiredArguments: string[];
  resultType: string;
  possibleErrors: string[];
}

export interface HTMLAppAIAgentSession {
  ask(prompt: string, options?: { signal?: AbortSignal }): Promise<{ text: string; toolCalls: number }>;
  clear(): void;
  readonly history: { role: string; content: string }[];
  readonly tools: string[];
}

export interface HTMLAppWidgetTimeRange { startMs: number; endMs: number; upcomingLabel?: string; inProgressLabel?: string; completedLabel?: string; }
export type HTMLAppWidgetTimeFormat = "automatic" | "hoursMinutesSeconds" | "minutesSeconds" | "hoursMinutes" | "seconds" | "minutes" | "hours";
export type HTMLAppWidgetFamily = "systemSmall" | "systemMedium" | "systemLarge" | "systemExtraLarge" | "accessoryInline" | "accessoryCircular" | "accessoryRectangular";
export interface HTMLAppWidgetElement { type: "row" | "column" | "overlay" | "text" | "symbol" | "image" | "timer" | "progress" | "ring" | "spacer" | "divider" | "circle" | "rectangle" | "capsule" | "lineChart" | "barChart" | "waveform" | "gauge" | "segmentedMeter" | "route" | "path" | "gradient"; children?: HTMLAppWidgetElement[]; text?: string; field?: "title" | "subtitle" | "value" | "unit" | "footer" | "eyebrow"; systemSymbol?: string; symbolRenderingMode?: "monochrome" | "hierarchical" | "palette" | "multicolor"; imageBase64?: string; timeFormat?: HTMLAppWidgetTimeFormat; progress?: number; alignment?: "leading" | "center" | "trailing"; verticalAlignment?: "top" | "center" | "bottom" | "firstTextBaseline"; spacing?: number; padding?: number; fontSize?: number; fontWeight?: "regular" | "medium" | "semibold" | "bold" | "heavy"; fontDesign?: "default" | "rounded" | "serif" | "monospaced"; lineLimit?: number; minimumScale?: number; foregroundHex?: string; backgroundHex?: string; borderHex?: string; borderWidth?: number; cornerRadius?: number; opacity?: number; width?: number; height?: number; expand?: boolean; accessibilityLabel?: string; samples?: number[]; points?: { x: number; y: number }[]; colors?: string[]; minimum?: number; maximum?: number; lineWidth?: number; segments?: number; closed?: boolean; }
export type HTMLAppSystemControlValue = boolean | number | string;
export type HTMLAppSystemControlAction = {kind: "open"; route?: string} | {kind: "set"; key: string; value: HTMLAppSystemControlValue} | {kind: "increment"; key: string; step: number} | {kind: "event"; key?: string; value?: HTMLAppSystemControlValue} | {kind: "activity.start" | "activity.update" | "activity.pause" | "activity.resume" | "activity.end" | "activity.complete"; activityID: string} | {kind: "notification.schedule"; notification: {id: string; title: string; body: string; delaySeconds: number}} | {kind: "notification.cancel"; notification: {id: string}};
export type HTMLAppSystemControlDefinition = {id: string; title: string; systemSymbol?: string} & ({type: "toggle"; stateKey: string} | {type: "button"; action: HTMLAppSystemControlAction; activity?: Record<string, unknown>});
export interface HTMLAppSystemControlSnapshot { controls: {id: string; title: string; type: "button" | "toggle"; systemSymbol: string; stateKey?: string; action?: string}[]; values: Record<string, HTMLAppSystemControlValue>; events: {id: string; controlID: string; action: string; timestampMs: number; key?: string; value?: HTMLAppSystemControlValue}[]; }
export interface HTMLAppDynamicWidgetSnapshot { timeRange?: HTMLAppWidgetTimeRange; display?: "countdown" | "elapsed" | "remainingProgress" | "elapsedProgress"; deadlineMs?: number; timeFormat?: HTMLAppWidgetTimeFormat; automaticStatus?: boolean; content?: HTMLAppWidgetElement; familyContent?: Partial<Record<HTMLAppWidgetFamily, HTMLAppWidgetElement>>; value?: string; [key: string]: unknown; }
export type HTMLAppControlField = { id: string; title: string; disabled?: boolean } & (
  | { type: "toggle"; value: boolean }
  | { type: "slider"; value: number; min: number; max: number; step?: number }
  | { type: "choice"; value: string; options: { id: string; title: string }[] }
  | { type: "text"; value: string }
);
export type HTMLAppControlResult = { cancelled: true } | { cancelled: false; values: Record<string, boolean | number | string> };
export interface HTMLAppNativeAPI {
  readonly protocolVersion: number;
  call<T = unknown>(method: HTMLAppNativeMethod, args?: Record<string, unknown>, options?: { signal?: AbortSignal }): Promise<T>;
  capabilities: (() => Promise<HTMLAppNativeCapabilitySnapshot>) & {
    list(): Promise<HTMLAppNativeCapabilitySnapshot>;
    has(method: HTMLAppNativeMethod): Promise<boolean>;
    describe(method: HTMLAppNativeMethod): Promise<HTMLAppNativeCapabilityDescriptor>;
  };
  permissions: {
    status(permission: string): Promise<{ hostPolicy: "ask" | "allow" | "deny"; systemAuthorization: string; available: boolean; canRequest: boolean; settingsRequired: boolean; note: string }>;
    request(permission: string): Promise<{ hostAllowed: boolean }>;
    openSettings(): Promise<{ opened: boolean }>;
  };
  screens: { configure(options: {items: {id: string; title: string; symbol: string; badge?: string}[]; selected?: string}): Promise<{enabled: boolean}>; go(id: string): Promise<boolean> };
  camera: { capturePhoto(options?: Record<string, unknown>): Promise<unknown>; startFrames(options: {frame: HTMLAppNativeFrame; camera?: "front" | "back"}): Promise<{started: boolean}>; captureFrame(): Promise<{url: string; sequence: number; width: number; height: number; reusedAfterCaptures: number}>; stopFrames(): Promise<unknown> };
  map: { show(options: Record<string, unknown>): Promise<unknown>; embed(options: {frame: HTMLAppNativeFrame; center?: {latitude: number; longitude: number}; span?: number; annotations?: {id: string; latitude: number; longitude: number; title?: string}[]; routes?: {latitude: number; longitude: number}[][]}): Promise<unknown>; hide(): Promise<unknown>; onSelect(callback: (event: {id: string}) => void): () => void };
  scene: { show(options: {frame: HTMLAppNativeFrame; ar?: boolean; objects: {id: string; shape: "box" | "sphere"; position: [number, number, number]; size: number; color?: string}[]}): Promise<unknown>; hide(): Promise<unknown>; onSelect(callback: (event: {id: string}) => void): () => void };
  motion: { start(options?: {frequency?: number}): Promise<unknown>; stop(): Promise<unknown>; onData(callback: (event: {timestamp: number; acceleration: HTMLAppXYZ; gravity: HTMLAppXYZ; rotationRate: HTMLAppXYZ; attitude: {roll: number; pitch: number; yaw: number}}) => void): () => void; pedometer(days?: number): Promise<unknown>; altitude(): Promise<unknown> };
  coreML: { load(url: string): Promise<{id: string; inputs: string[]; outputs: string[]}>; infer(modelID: string, imageURL: string): Promise<unknown>; unload(modelID: string): Promise<unknown> };
  music: { loadBank(url: string, program?: number): Promise<unknown>; noteOn(note: number, velocity?: number): Promise<unknown>; noteOff(note: number): Promise<unknown>; stop(): Promise<unknown> };
  midi: { destinations(): Promise<{destinations: {index: number; name: string}[]}>; send(destination: number, bytes: number[]): Promise<unknown> };
  liveActivities: { perform(id: string, action: "pause" | "resume" | "complete"): Promise<unknown>; start(definition: Record<string, unknown>): Promise<unknown>; update(id: string, state: Record<string, unknown>): Promise<unknown>; end(id: string): Promise<unknown>; list(): Promise<unknown> };
  controls: { configure(options: {appName?: string; controls: HTMLAppSystemControlDefinition[]; initial?: Record<string, HTMLAppSystemControlValue>}): Promise<{published: boolean; count: number; instructions: string}>; read(): Promise<HTMLAppSystemControlSnapshot>; set(values: Record<string, HTMLAppSystemControlValue>): Promise<HTMLAppSystemControlSnapshot>; acknowledge(ids: string[]): Promise<{acknowledged: boolean}>; remove(): Promise<{removed: boolean}>; };
  widgets: {
    configure(definition: { id: string; name?: string; families: string[]; snapshot: HTMLAppDynamicWidgetSnapshot; [key: string]: unknown }): Promise<unknown>;
    list(): Promise<unknown>;
    remove(id?: string): Promise<unknown>;
    reload(): Promise<unknown>;
  };
  backend: {
    subscribe(session: string): Promise<Record<string, unknown>>;
    unsubscribe(session: string): Promise<Record<string, unknown>>;
    request(options: { path: string; method?: "GET" | "POST" | "PUT" | "PATCH" | "DELETE"; body?: Record<string, unknown>; session?: string }): Promise<Record<string, unknown>>;
    status(): Promise<{ linked: boolean; canNotify: boolean; sdkVersion?: number; apiBaseURL?: string; pushConfigured?: boolean; state?: string; publicKey?: string }>;
    read(): Promise<{ data: unknown }>;
    notify(options: { title?: string; body: string }): Promise<{ accepted: boolean }>;
  };
  network: {
    status(): Promise<{ status: "unknown" | "satisfied" | "unsatisfied" | "requires_connection"; online: boolean; interface: string; expensive: boolean; constrained: boolean }>;
    request(args: { url: string; method?: "GET" | "POST" | "PUT" | "PATCH" | "DELETE" | "HEAD"; headers?: Record<string, string>; body?: string; signal?: AbortSignal }): Promise<{ status: number; ok: boolean; body: string; contentType: string }>;
    allowedDomains(): Promise<{ domains: string[] }>;
    revokeDomain(host: string): Promise<{ revoked: boolean }>;
  };
  location: {
    backgroundEnable(distanceMeters?: number): Promise<{enabled: boolean; authorization: string}>;
    backgroundDisable(): Promise<{enabled: boolean}>;
    backgroundStatus(): Promise<{enabled: boolean; authorization: string}>;
    backgroundRead(): Promise<{samples: {latitude: number; longitude: number; accuracy: number; timestampMs: number}[]}>;
    geocode(query: string): Promise<{ results: { latitude: number; longitude: number; formattedAddress: string; approximate: boolean }[]; source: string }>;
    distance(latitude1: number, longitude1: number, latitude2: number, longitude2: number): Promise<{ meters: number; kilometers: number; miles: number; kind: "great_circle" }>;
    reverseGeocode(latitude: number, longitude: number): Promise<{ formattedAddress: string; approximate: boolean }>;
    roadSpeedLimit(latitude: number, longitude: number): Promise<unknown>;
  };
  ui: {
    controls(args: { title?: string; fields: HTMLAppControlField[] }, request?: { signal?: AbortSignal }): Promise<HTMLAppControlResult>;
    alert(args: { title?: string; message?: string; actions?: { id: string; title: string; style?: "cancel" | "default" | "destructive" }[] }): Promise<{ id?: string; index?: number; cancelled: boolean }>;
    menu(args: { title?: string; message?: string; actions: { id: string; title: string; style?: string }[] }): Promise<{ id?: string; index?: number; cancelled: boolean }>;
    datePicker(args: { title?: string; mode?: "date" | "time" | "dateTime"; value?: string; timestampMS?: number }): Promise<{ cancelled: boolean; value?: string; timestampMS?: number }>;
    colorPicker(args?: { hex?: string; alpha?: boolean }): Promise<{ cancelled: boolean; hex?: string; alpha?: number }>;
    list(args: { title?: string; items: { id: string; title: string; detail?: string; symbol?: string }[]; allowsRefresh?: boolean }): Promise<{ cancelled: boolean; id?: string; index?: number; sessionID?: string }>;
    listUpdate(items: { id: string; title: string; detail?: string; symbol?: string }[], sessionID?: string): Promise<{ updated: boolean; count: number; sessionID: string }>;
    listDismiss(): Promise<{ dismissed: boolean }>;
  };
  video: { capture(options?: { maxDuration?: number }): Promise<{ url: string; name: string; size: number; mimeType: string }> };
  audio: {
    record(options?: { maxDuration?: number }): Promise<{ recording: boolean; url: string; mimeType: "audio/mp4"; maxDuration: number }>;
    stopRecording(): Promise<{ recording: false; url: string; mimeType: "audio/mp4"; size: number; duration: number }>;
    cancelRecording(): Promise<{ cancelled: boolean }>;
    levels(): Promise<{ recording: boolean; levelDB: number; peakDB?: number; duration?: number }>;
    play(url: string): Promise<{ playing: boolean; duration: number }>;
    pause(): Promise<{ playing: boolean }>;
    stop(): Promise<{ playing: false }>;
  };
  db: {
    search(collection: string, text: string, limit?: number): Promise<{ items: { id: string; document: unknown }[] }>;
    searchFullText(collection: string, text: string, limit?: number): Promise<{ items: { id: string; document: unknown; rank: number }[] }>;
    vectorSearch(collection: string, text: string, limit?: number): Promise<{ items: { id: string; document: unknown; score: number }[] }>;
  };
  ai: {
    available(): Promise<{ available: boolean; remainingRequests: number; streaming: boolean }>;
    complete(options: { prompt: string; system?: string; maxTokens?: number; json?: boolean }): Promise<{ text: string }>;
    localComplete(options: ({ prompt: string; messages?: never } | { messages: Array<{ role: "user" | "assistant"; content: string }>; prompt?: never }) & { signal?: AbortSignal; system?: string; format?: "text" | "json" | "structured"; fallback?: "cloud" }): Promise<{ text: string; format: string; provider?: "cloud"; fallback?: boolean; json?: { answer: string; summary: string; confident: boolean } }>;
    stream(options: { prompt: string; system?: string; maxTokens?: number; signal?: AbortSignal; onToken?: (token: string, detail: { requestID: string; delta: string; done: boolean }) => void }): Promise<{ text: string; requestID: string }>;
    createSession(settings?: { system?: string; tools?: string[] }): HTMLAppAIAgentSession;
  };
  events: { on(name: string, handler: (detail: unknown) => void): () => void };
}

export interface HTMLAppDataAPI {
  collection(name: string): {
    put(id: string, document: Record<string, unknown>): Promise<{ ok: boolean }>;
    get(id: string): Promise<Record<string, unknown> | null>;
    remove(id: string): Promise<{ ok: boolean }>;
    query(options?: { cursor?: string; limit?: number }): Promise<{ items: { id: string; document: unknown }[]; cursor?: string }>;
    search(text: string, limit?: number): Promise<{ items: unknown[] }>;
    count(): Promise<{ count: number }>;
  };
  kv: { get(key: string): Promise<unknown>; set(key: string, value: unknown): Promise<unknown>; remove(key: string): Promise<unknown> };
  migrate(name: string, version: number, migrations: Record<number, (context: unknown) => Promise<void>>): Promise<number>;
}

export interface HTMLAppRuntimeAPI {
  runOperation<T>(name: string, work: (context: { signal: AbortSignal }) => Promise<T>, onState?: (state: unknown) => void): Promise<T>;
  cancelOperation(name: string): boolean;
  readonly activeOperations: string[];
  readonly isVisible: boolean;
  onActive(handler: (detail: unknown) => void): () => void;
  onInactive(handler: (detail: unknown) => void): () => void;
  onBackground(handler: (detail: unknown) => void): () => void;
  onResume(handler: (detail: unknown) => void): () => void;
}

declare global {
  interface Window { HTMLAppNative?: HTMLAppNativeAPI; HTMLAppData?: HTMLAppDataAPI; HTMLAppRuntime?: HTMLAppRuntimeAPI }
}
