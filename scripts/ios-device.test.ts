import { describe, expect, test } from "bun:test";

import {
	isRecoverableLockError,
	resolveBuildDestination,
	resolveWaitForHandoff,
} from "./ios-device.ts";

describe("isRecoverableLockError", () => {
	test("recognizes the exact locked-device launch failure", () => {
		const error = new Error(
			"Unable to launch cc.trails.app because the device was not, or could not be, unlocked.",
		);

		expect(isRecoverableLockError(error)).toBe(true);
	});

	test("rejects unrelated errors", () => {
		expect(isRecoverableLockError(new Error("network timeout"))).toBe(false);
	});
});

describe("resolveBuildDestination", () => {
	test("uses generic iOS destination in build-only mode", () => {
		expect(resolveBuildDestination(true)).toBe("generic/platform=iOS");
	});

	test("uses a physical device id for install and launch mode", () => {
		expect(resolveBuildDestination(false, "abc123")).toBe("id=abc123");
	});
});

describe("resolveWaitForHandoff", () => {
	test("waits by default", () => {
		expect(resolveWaitForHandoff([])).toBe(true);
	});

	test("allows the old console-attached handoff explicitly", () => {
		expect(resolveWaitForHandoff(["--wait"], false)).toBe(true);
		expect(resolveWaitForHandoff(["--attach-console"], false)).toBe(true);
	});

	test("allows explicit no-wait override", () => {
		expect(resolveWaitForHandoff(["--no-wait"], true)).toBe(false);
		expect(resolveWaitForHandoff(["--detach"], true)).toBe(false);
	});
});
