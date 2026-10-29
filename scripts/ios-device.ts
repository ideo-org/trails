import {
	closeSync,
	createWriteStream,
	existsSync,
	mkdirSync,
	openSync,
	readdirSync,
	rmSync,
} from "node:fs";
import path from "node:path";

type XcDevice = {
	available?: boolean;
	identifier?: string;
	interface?: string;
	modelName?: string;
	name?: string;
	operatingSystemVersion?: string;
	platform?: string;
	simulator?: boolean;
	state?: string;
	isAvailable?: boolean;
};

const ROOT_DIR = path.resolve(import.meta.dir, "..");

function normalizeJustValue(value: string | undefined, key: string) {
	const trimmed = value?.trim() ?? "";
	const prefix = `${key}=`;
	return trimmed.startsWith(prefix) ? trimmed.slice(prefix.length) : trimmed;
}

function resolveValue(
	envValue: string | undefined,
	key: string,
	fallback: string,
) {
	const normalized = normalizeJustValue(envValue, key);
	if (!normalized || normalized.includes("=")) {
		return fallback;
	}
	return normalized;
}

function expandPath(input: string) {
	if (input === "~") {
		return process.env.HOME ?? input;
	}
	if (input.startsWith("~/")) {
		return path.join(process.env.HOME ?? "", input.slice(2));
	}
	if (path.isAbsolute(input)) {
		return input;
	}
	return path.join(ROOT_DIR, input);
}

const SCHEME = process.env.IOS_SCHEME || "Trails";
const PROJECT = path.join(ROOT_DIR, "ios", "Trails.xcodeproj");
const CONFIGURATION = resolveValue(
	process.env.IOS_CONFIGURATION,
	"configuration",
	"Debug",
);
const REQUESTED_DEVICE = resolveValue(process.env.IOS_DEVICE, "device", "");
const DERIVED_DATA = expandPath(
	resolveValue(
		process.env.IOS_DERIVED_DATA,
		"derived_data",
		"build/ios/DerivedData",
	),
);
function defaultSourcePackagesDir() {
	return path.join(DERIVED_DATA, "SourcePackages");
}

function resolveSourcePackagesDir() {
	const requested = normalizeJustValue(
		process.env.IOS_SOURCE_PACKAGES_DIR,
		"source_packages",
	);
	const fallback = defaultSourcePackagesDir();
	if (!requested) {
		return fallback;
	}

	const resolved = expandPath(requested);
	const derivedDataRoot = `${DERIVED_DATA}${path.sep}`;
	if (resolved === DERIVED_DATA || resolved.startsWith(derivedDataRoot)) {
		return resolved;
	}

	console.warn(
		`IOS_SOURCE_PACKAGES_DIR=${resolved} is outside DerivedData. Using ${fallback} so Xcode can materialize binary SwiftPM artifacts.`,
	);
	return fallback;
}

const SOURCE_PACKAGES_DIR = resolveSourcePackagesDir();
const REQUESTED_BUNDLE_ID = resolveValue(
	process.env.IOS_BUNDLE_ID,
	"bundle_id",
	"",
);
const SHOULD_RESET_SOURCE_PACKAGES = /^(1|true|yes|on)$/i.test(
	resolveValue(
		process.env.IOS_RESET_SOURCE_PACKAGES,
		"reset_source_packages",
		"false",
	),
);
const LOCK_RETRY_DELAY_MS = Number.parseInt(
	process.env.IOS_LOCK_RETRY_DELAY_MS ?? "5000",
	10,
);
const LAUNCH_LOGS_DIR = path.join(DERIVED_DATA, SCHEME, "Logs", "Launch");
const TEST_RESULTS_DIR = expandPath(
	resolveValue(
		process.env.IOS_TEST_RESULTS_DIR,
		"test_results_dir",
		"build/ios/TestResults",
	),
);
const GUM_PATH = Bun.which("gum");

class CommandError extends Error {
	command: string[];
	exitCode: number;
	stderr: string;
	stdout: string;

	constructor(
		command: string[],
		exitCode: number,
		stdout: string,
		stderr: string,
	) {
		super(
			(stderr || stdout).trim() || `${command[0]} exited with code ${exitCode}`,
		);
		this.name = "CommandError";
		this.command = command;
		this.exitCode = exitCode;
		this.stdout = stdout;
		this.stderr = stderr;
	}
}

export function resolveWaitForHandoff(
	argv: string[],
	fallback = true,
) {
	if (argv.includes("--wait") || argv.includes("--attach-console")) {
		return true;
	}
	if (argv.includes("--no-wait") || argv.includes("--detach")) {
		return false;
	}
	return fallback;
}

function parseArgs(argv: string[]) {
	const buildOnly = argv.includes("--build-only");
	const testOnly = argv.includes("--test");
	const list = argv.includes("--list");
	const listSimulators = argv.includes("--list-simulators");
	const waitForHandoff = resolveWaitForHandoff(argv);
	const simulatorArgIndex = argv.indexOf("--simulator");
	const simulator =
		simulatorArgIndex !== -1
			? normalizeJustValue(argv[simulatorArgIndex + 1], "simulator")
			: undefined;
	return { buildOnly, testOnly, list, listSimulators, simulator, waitForHandoff };
}


export function resolveBuildDestination(
	buildOnly: boolean,
	deviceId?: string,
) {
	// Always build for generic iOS device to bypass Xcode developer disk image mounting errors
	// on newer iOS versions (like iOS 27). `devicectl` handles installation afterwards.
	return "generic/platform=iOS";
}

async function run(command: string[]) {
	const proc = Bun.spawn(command, {
		env: process.env,
		stdin: "inherit",
		stdout: "inherit",
		stderr: "inherit",
	});
	const exitCode = await proc.exited;
	if (exitCode !== 0) {
		throw new Error(`${command[0]} exited with code ${exitCode}`);
	}
}

async function capture(command: string[]) {
	const proc = Bun.spawn(command, {
		env: process.env,
		stdout: "pipe",
		stderr: "pipe",
	});
	const [stdout, stderr, exitCode] = await Promise.all([
		new Response(proc.stdout).text(),
		new Response(proc.stderr).text(),
		proc.exited,
	]);
	if (exitCode !== 0) {
		throw new CommandError(command, exitCode, stdout, stderr);
	}
	return stdout;
}

async function runBestEffort(command: string[]) {
	const proc = Bun.spawn(command, {
		env: process.env,
		stdin: "inherit",
		stdout: "inherit",
		stderr: "inherit",
	});
	await proc.exited;
}

function ensureLaunchLogsDir() {
	mkdirSync(LAUNCH_LOGS_DIR, { recursive: true });
}

function ensureTestResultsDir() {
	mkdirSync(TEST_RESULTS_DIR, { recursive: true });
}

function pad(value: number) {
	return String(value).padStart(2, "0");
}

function timestampForFile(date = new Date()) {
	const year = date.getFullYear();
	const month = pad(date.getMonth() + 1);
	const day = pad(date.getDate());
	const hours = pad(date.getHours());
	const minutes = pad(date.getMinutes());
	const seconds = pad(date.getSeconds());
	const offsetMinutes = -date.getTimezoneOffset();
	const sign = offsetMinutes >= 0 ? "+" : "-";
	const absoluteOffsetMinutes = Math.abs(offsetMinutes);
	const offsetHours = pad(Math.floor(absoluteOffsetMinutes / 60));
	const offsetRemainder = pad(absoluteOffsetMinutes % 60);
	return `${year}.${month}.${day}_${hours}-${minutes}-${seconds}-${sign}${offsetHours}${offsetRemainder}`;
}

function buildRunArtifactPaths() {
	ensureLaunchLogsDir();
	ensureTestResultsDir();
	const timestamp = timestampForFile();
	return {
		buildResultBundlePath: path.join(
			LAUNCH_LOGS_DIR,
			`Run-${SCHEME}-${timestamp}.xcresult`,
		),
		uiTestResultBundlePath: path.join(
			TEST_RESULTS_DIR,
			`UITest-${SCHEME}-${timestamp}.xcresult`,
		),
		installLogPath: path.join(
			LAUNCH_LOGS_DIR,
			`Install-${SCHEME}-${timestamp}.log`,
		),
		launchLogPath: path.join(
			LAUNCH_LOGS_DIR,
			`Launch-${SCHEME}-${timestamp}.log`,
		),
	};
}

export function isRecoverableLockError(error: unknown) {
	if (!(error instanceof Error)) {
		return false;
	}

	const message = error.message.toLowerCase();
	return (
		message.includes("locked") ||
		message.includes("unlock") ||
		message.includes("passcode") ||
		message.includes("not available because the device is locked")
	);
}

function sleep(ms: number) {
	return new Promise((resolve) => setTimeout(resolve, ms));
}

function escapeAppleScriptString(value: string) {
	return value.replace(/\\/g, "\\\\").replace(/"/g, '\\"');
}

async function sendMacNotification(title: string, message: string) {
	if (process.platform !== "darwin") {
		return;
	}

	try {
		await capture([
			"osascript",
			"-e",
			`display notification "${escapeAppleScriptString(message)}" with title "${escapeAppleScriptString(title)}"`,
		]);
	} catch {
	}
}

async function printSection(title: string) {
	if (!GUM_PATH) {
		console.log(title);
		return;
	}

	await runBestEffort([
		GUM_PATH,
		"style",
		"--foreground",
		"212",
		"--bold",
		title,
	]);
}

async function printLockedWait(label: string, deviceName: string) {
	const message = `${label} is waiting for ${deviceName} to unlock.\nRetrying automatically every ${Math.round(LOCK_RETRY_DELAY_MS / 1000)}s.`;
	if (!GUM_PATH) {
		console.log(message);
		return;
	}

	await runBestEffort([
		GUM_PATH,
		"style",
		"--border",
		"rounded",
		"--border-foreground",
		"214",
		"--foreground",
		"230",
		"--padding",
		"0",
		"1",
		message,
	]);
}

async function printArtifact(label: string, artifactPath: string) {
	const message = `${label}: ${artifactPath}`;
	if (!GUM_PATH) {
		console.log(message);
		return;
	}

	await runBestEffort([GUM_PATH, "style", "--foreground", "244", message]);
}

async function retryWhenLocked<T>(
	label: string,
	deviceName: string,
	action: (attempt: number) => Promise<T>,
) {
	let notified = false;

	for (let attempt = 1; ; attempt += 1) {
		try {
			return await action(attempt);
		} catch (error) {
			if (!isRecoverableLockError(error)) {
				throw error;
			}

			if (!notified) {
				notified = true;
				await sendMacNotification(
					"Trails iOS run is waiting for your iPhone",
					`${deviceName} appears to be locked. Unlock it and the launch will retry automatically.`,
				);
			}

			await printLockedWait(label, deviceName);
			await sleep(LOCK_RETRY_DELAY_MS);
		}
	}
}

async function runDeviceAction<T>(
	label: string,
	deviceName: string,
	waitForUnlock: boolean,
	action: (attempt: number) => Promise<T>,
) {
	if (waitForUnlock) {
		return retryWhenLocked(label, deviceName, action);
	}

	try {
		return await action(1);
	} catch (error) {
		if (!isRecoverableLockError(error)) {
			throw error;
		}

		await sendMacNotification(
			`Trails iOS ${label.toLowerCase()} needs your iPhone`,
			`${deviceName} appears to be locked. Unlock it and rerun the install handoff.`,
		);
		throw new Error(
			`${label} could not continue because ${deviceName} appears to be locked. Unlock it and rerun the install handoff.`,
		);
	}
}

async function runCaptureLogged(command: string[], logPath: string) {
	closeSync(openSync(logPath, "a"));
	const proc = Bun.spawn([...command, "--log-output", logPath], {
		env: process.env,
		stdout: "pipe",
		stderr: "pipe",
	});
	const [stdout, stderr, exitCode] = await Promise.all([
		new Response(proc.stdout).text(),
		new Response(proc.stderr).text(),
		proc.exited,
	]);

	if (stdout) {
		process.stdout.write(stdout);
	}
	if (stderr) {
		process.stderr.write(stderr);
	}

	if (exitCode !== 0) {
		throw new CommandError(command, exitCode, stdout, stderr);
	}
}

async function streamLaunchToConsole(command: string[], logPath: string) {
	closeSync(openSync(logPath, "a"));
	const logStream = createWriteStream(logPath, { flags: "a" });
	const proc = Bun.spawn(command, {
		env: process.env,
		stdout: "pipe",
		stderr: "pipe",
	});

	let stdoutText = "";
	let stderrText = "";

	const forward = async (
		stream: ReadableStream<Uint8Array> | null,
		target: NodeJS.WriteStream,
		collect: (text: string) => void,
	) => {
		if (!stream) {
			return;
		}

		const reader = stream.getReader();
		try {
			while (true) {
				const { done, value } = await reader.read();
				if (done) {
					break;
				}
				const chunk = Buffer.from(value);
				const text = chunk.toString("utf8");
				collect(text);
				target.write(chunk);
				logStream.write(chunk);
			}
		} finally {
			reader.releaseLock();
		}
	};

	const [exitCode] = await Promise.all([
		proc.exited,
		forward(proc.stdout, process.stdout, (text) => {
			stdoutText += text;
		}),
		forward(proc.stderr, process.stderr, (text) => {
			stderrText += text;
		}),
	]);

	await new Promise<void>((resolve, reject) => {
		logStream.end((error) => {
			if (error) {
				reject(error);
				return;
			}
			resolve();
		});
	});

	if (exitCode !== 0) {
		throw new CommandError(command, exitCode, stdoutText, stderrText);
	}
}

function isPhysicalIOSDevice(device: XcDevice) {
	return (
		device.available === true &&
		device.simulator !== true &&
		typeof device.identifier === "string" &&
		typeof device.platform === "string" &&
		device.platform.toLowerCase().includes("iphoneos")
	);
}

function formatDevice(device: XcDevice) {
	return `${device.name ?? "Unknown"} | ${device.identifier ?? "unknown-id"} | ${device.interface ?? "unknown"} | ${device.operatingSystemVersion ?? "unknown OS"}`;
}

function isIPhone(device: XcDevice) {
	const haystack =
		`${device.name ?? ""} ${device.modelName ?? ""}`.toLowerCase();
	return haystack.includes("iphone");
}

function rankDevice(device: XcDevice) {
	let score = 0;
	if (device.interface !== "usb") score += 10;
	if (!isIPhone(device)) score += 1;
	return score;
}

function findDevice(devices: XcDevice[], requested: string) {
	const physicalDevices = devices
		.filter(isPhysicalIOSDevice)
		.sort((left, right) => rankDevice(left) - rankDevice(right));

	if (!requested) {
		return physicalDevices[0];
	}

	const requestedLower = requested.toLowerCase();
	return physicalDevices.find((device) => {
		return (
			device.identifier === requested ||
			device.name?.toLowerCase() === requestedLower ||
			device.name?.toLowerCase().includes(requestedLower)
		);
	});
}

async function readDevices() {
	const stdout = await capture(["xcrun", "xcdevice", "list"]);
	const parsed = JSON.parse(stdout);
	if (!Array.isArray(parsed)) {
		throw new Error("Unexpected output from `xcrun xcdevice list`.");
	}
	return parsed as XcDevice[];
}

async function readSimulators(): Promise<XcDevice[]> {
	const stdout = await capture(["xcrun", "simctl", "list", "--json", "devices"]);
	const parsed = JSON.parse(stdout);
	const devices: XcDevice[] = [];
	for (const runtime of Object.values(parsed.devices) as any[]) {
		for (const device of runtime) {
			devices.push({
				...device,
				identifier: device.udid,
				simulator: true,
			});
		}
	}
	return devices;
}

function isBootedSimulator(device: XcDevice) {
	return device.state === "Booted";
}

function findSimulator(simulators: XcDevice[], requested?: string) {
	if (requested === "booted") {
		return simulators.find(isBootedSimulator);
	}
	if (requested) {
		const requestedLower = requested.toLowerCase();
		return simulators.find((device) => {
			return (
				device.identifier === requested ||
				device.name?.toLowerCase() === requestedLower ||
				device.name?.toLowerCase().includes(requestedLower)
			);
		});
	}
	return simulators.find(isBootedSimulator) ?? simulators[0];
}


async function readBundleId(appPath: string) {
	if (REQUESTED_BUNDLE_ID) {
		return REQUESTED_BUNDLE_ID;
	}

	const infoPlist = path.join(appPath, "Info.plist");
	const bundleId = (
		await capture([
			"/usr/libexec/PlistBuddy",
			"-c",
			"Print :CFBundleIdentifier",
			infoPlist,
		])
	).trim();
	if (!bundleId) {
		throw new Error(`Could not read CFBundleIdentifier from ${infoPlist}.`);
	}
	return bundleId;
}

function resetSourcePackagesCache() {
	mkdirSync(SOURCE_PACKAGES_DIR, { recursive: true });

	if (!SHOULD_RESET_SOURCE_PACKAGES) {
		return;
	}

	console.log(
		"Resetting SourcePackages cache because IOS_RESET_SOURCE_PACKAGES=true...",
	);
	for (const entry of [
		"artifacts",
		"checkouts",
		"repositories",
		"workspace-state.json",
	]) {
		const target = path.join(SOURCE_PACKAGES_DIR, entry);
		if (existsSync(target)) {
			rmSync(target, { recursive: true, force: true });
		}
	}
}

async function resolvePackageDependencies() {
	resetSourcePackagesCache();
	mkdirSync(DERIVED_DATA, { recursive: true });
	mkdirSync(SOURCE_PACKAGES_DIR, { recursive: true });

	console.log("Resolving package dependencies (including binary XCFrameworks)...");
	await run([
		"xcodebuild",
		"-resolvePackageDependencies",
		"-project",
		PROJECT,
		"-clonedSourcePackagesDirPath",
		SOURCE_PACKAGES_DIR,
	]);
}

async function buildApp(
	destination: string,
	configuration: string,
	resultBundlePath: string,
) {
	await resolvePackageDependencies();
	await run([
		"xcodebuild",
		"build",
		"-scheme",
		SCHEME,
		"-project",
		PROJECT,
		"-configuration",
		configuration,
		"-destination",
		destination,
		"-derivedDataPath",
		DERIVED_DATA,
		"-clonedSourcePackagesDirPath",
		SOURCE_PACKAGES_DIR,
		`TRACKER_HOST=${process.env.TRACKER_HOST || "vm.ideomind.org"}`,
		"-resultBundlePath",
		resultBundlePath,
		"-allowProvisioningUpdates",
		"-allowProvisioningDeviceRegistration",
	]);
}

async function runUITests(
	destination: string,
	configuration: string,
	resultBundlePath: string,
) {
	await resolvePackageDependencies();
	await run([
		"xcodebuild",
		"test",
		"-scheme",
		SCHEME,
		"-project",
		PROJECT,
		"-configuration",
		configuration,
		"-destination",
		destination,
		"-derivedDataPath",
		DERIVED_DATA,
		"-clonedSourcePackagesDirPath",
		SOURCE_PACKAGES_DIR,
		`TRACKER_HOST=${process.env.TRACKER_HOST || "vm.ideomind.org"}`,
		"-resultBundlePath",
		resultBundlePath,
		"-allowProvisioningUpdates",
		"-allowProvisioningDeviceRegistration",
	]);
}

function findBuiltApp(productsDir: string): string | null {
	if (!existsSync(productsDir)) {
		return null;
	}

	const entries = readdirSync(productsDir, { withFileTypes: true });
	for (const entry of entries) {
		const entryPath = path.join(productsDir, entry.name);
		if (entry.isDirectory()) {
			if (entry.name.endsWith(".app") && !entry.name.endsWith(".appex")) {
				return entryPath;
			}
			const nested = findBuiltApp(entryPath);
			if (nested) {
				return nested;
			}
		}
	}

	return null;
}

async function findAppBundle() {
	const productsDir = path.join(DERIVED_DATA, "Build", "Products");
	const appPath = findBuiltApp(productsDir);
	if (!appPath) {
		throw new Error(`Could not find built app bundle under ${productsDir}.`);
	}
	return appPath;
}

async function main() {
	const args = parseArgs(process.argv.slice(2));

	if (args.list) {
		const devices = await readDevices();
		const physicalDevices = devices
			.filter(isPhysicalIOSDevice)
			.sort((left, right) => rankDevice(left) - rankDevice(right));

		if (physicalDevices.length === 0) {
			console.log("No available physical iOS devices found.");
			return;
		}

		for (const device of physicalDevices) {
			console.log(formatDevice(device));
		}
		return;
	}

	if (args.listSimulators) {
		const simulators = await readSimulators();
		if (simulators.length === 0) {
			console.log("No available simulators found.");
			return;
		}
		for (const simulator of simulators) {
			console.log(`${formatDevice(simulator)} | ${simulator.state}`);
		}
		return;
	}

	let device: XcDevice | undefined;
	let isSimulator = false;

	if (args.simulator !== undefined) {
		isSimulator = true;
		const simulators = await readSimulators();
		device = findSimulator(simulators, args.simulator);
		if (!device?.identifier) {
			console.error("No available simulator found.");
			if (args.simulator) {
				console.error(`Requested simulator: ${args.simulator}`);
			}
			process.exit(1);
		}
		console.log(`Target device: ${formatDevice(device)}`);
	} else if (!args.buildOnly || args.testOnly) {
		const devices = await readDevices();
		device = findDevice(devices, REQUESTED_DEVICE);
		if (!device?.identifier) {
			console.error("No available physical iOS device found.");
			if (REQUESTED_DEVICE) {
				console.error(`Requested device: ${REQUESTED_DEVICE}`);
			}
			console.error("Run `just ios-devices` to inspect detected devices.");
			process.exit(1);
		}

		console.log(`Target device: ${formatDevice(device)}`);
	} else {
		console.log("Build-only mode: using generic iOS destination.");
	}

	const runArtifacts = buildRunArtifactPaths();
	const destination = resolveBuildDestination(args.buildOnly, device?.identifier);

	if (args.testOnly) {
		await printSection(
			`Testing ${SCHEME} (${CONFIGURATION}) on ${device!.name ?? device!.identifier}...`,
		);
		await runUITests(destination, CONFIGURATION, runArtifacts.uiTestResultBundlePath);
		if (existsSync(runArtifacts.uiTestResultBundlePath)) {
			await printArtifact(
				"xcodebuild UI test result bundle",
				runArtifacts.uiTestResultBundlePath,
			);
		}
		console.log(`iOS UI tests completed for ${SCHEME}.`);
		return;
	}

	await printSection(
		args.buildOnly
			? `Building ${SCHEME} (${CONFIGURATION}) for generic iOS device...`
			: `Building ${SCHEME} (${CONFIGURATION}) for ${device!.name ?? device!.identifier}...`,
	);
	await buildApp(destination, CONFIGURATION, runArtifacts.buildResultBundlePath);
	if (existsSync(runArtifacts.buildResultBundlePath)) {
		await printArtifact(
			"xcodebuild result bundle",
			runArtifacts.buildResultBundlePath,
		);
	}

	const appPath = await findAppBundle();
	console.log(`App bundle: ${appPath}`);
	console.log(`DerivedData: ${DERIVED_DATA}`);
	console.log(`SourcePackages: ${SOURCE_PACKAGES_DIR}`);

	if (args.buildOnly) {
		console.log(`iOS build completed: ${appPath}`);
		return;
	}

	if (isSimulator) {
		if (device!.state !== "Booted") {
			await printSection(`Booting simulator ${device!.name}...`);
			await run(["open", "-a", "Simulator", "--args", "-CurrentDeviceUDID", device!.identifier!]);
			await run(["xcrun", "simctl", "bootstatus", device!.identifier!]);
		}

		await printSection("Installing app on simulator...");
		await run(["xcrun", "simctl", "install", device!.identifier!, appPath]);

		const bundleId = await readBundleId(appPath);
		await printSection(`Launching ${bundleId}...`);
		await run(
			args.waitForHandoff
				? [
						"xcrun",
						"simctl",
						"launch",
						"--console",
						device!.identifier!,
						bundleId,
					]
				: ["xcrun", "simctl", "launch", device!.identifier!, bundleId],
		);
	} else {
		await printSection("Installing app on device...");
		closeSync(openSync(runArtifacts.installLogPath, "a"));
		await printArtifact("Install log", runArtifacts.installLogPath);
		const deviceName = device!.name ?? device!.identifier!;
		await runDeviceAction(
			"Install",
			deviceName,
			args.waitForHandoff,
			async () => {
				await runCaptureLogged(
					[
						"xcrun",
						"devicectl",
						"device",
						"install",
						"app",
						"--device",
						device!.identifier!,
						appPath,
					],
					runArtifacts.installLogPath,
				);
			},
		);

		if (!args.waitForHandoff) {
			await sendMacNotification(
				`${SCHEME} installed on iPhone`,
				`Open ${SCHEME} on ${deviceName} and test the requested flow.`,
			);
			console.log(
				`Installed ${SCHEME} on ${deviceName}. Not attaching to the app console; open the app on the iPhone and test the requested flow.`,
			);
			return;
		}

		const bundleId = await readBundleId(appPath);
		await printSection(`Launching ${bundleId}...`);
		closeSync(openSync(runArtifacts.launchLogPath, "a"));
		await printArtifact("Launch console log", runArtifacts.launchLogPath);
		console.log(
			"Attaching to the app console. This command stays open like Xcode until the app exits.",
		);
		await runDeviceAction("Launch", deviceName, true, async () => {
			await streamLaunchToConsole(
				[
					"xcrun",
					"devicectl",
					"device",
					"process",
					"launch",
					"--device",
					device!.identifier!,
					"--terminate-existing",
					"--console",
					bundleId,
				],
				runArtifacts.launchLogPath,
			);
		});

	}


	console.log("The app launch session ended.");
}

if (import.meta.main) {
	main().catch((error) => {
		console.error("\niOS device run failed.");
		if (error instanceof Error) {
			console.error(error.message);
		} else {
			console.error(String(error));
		}
		process.exit(1);
	});
}
