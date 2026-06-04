import { activeProcessingState } from '$lib/stores/chat.svelte';
import { config } from '$lib/stores/settings.svelte';
import { STATS_UNITS } from '$lib/constants';
import type { ApiProcessingState, LiveProcessingStats, LiveGenerationStats } from '$lib/types';

export interface UseProcessingStateReturn {
	readonly processingState: ApiProcessingState | null;
	getProcessingDetails(): string[];
	getTechnicalDetails(): string[];
	getProcessingMessage(): string;
	getPromptProgressText(): string | null;
	getLiveProcessingStats(): LiveProcessingStats | null;
	getLiveGenerationStats(): LiveGenerationStats | null;
	shouldShowDetails(): boolean;
	startMonitoring(): void;
	stopMonitoring(): void;
}

/**
 * useProcessingState - Reactive processing state hook
 *
 * This hook provides reactive access to the processing state of the server.
 * It directly reads from chatStore's reactive state and provides
 * formatted processing details for UI display.
 *
 * **Features:**
 * - Real-time processing state via direct reactive state binding
 * - Context and output token tracking
 * - Tokens per second calculation
 * - Automatic updates when streaming data arrives
 * - Supports multiple concurrent conversations
 *
 * @returns Hook interface with processing state and control methods
 */
export function useProcessingState(): UseProcessingStateReturn {
	let isMonitoring = $state(false);
	let lastKnownState = $state<ApiProcessingState | null>(null);
	let lastKnownProcessingStats = $state<LiveProcessingStats | null>(null);

	// EMA-smoothed t/s — eliminates OS-scheduler jitter from cumulative average
	// α=0.25: smooth but still responsive. Skip token 1 (warmup anomaly).
	let smoothedTps = $state(0);

	// Derive processing state reactively from chatStore's direct state
	const processingState = $derived.by(() => {
		if (!isMonitoring) {
			return lastKnownState;
		}
		// Read directly from the reactive state export
		return activeProcessingState();
	});

	// Track last known state for keepStatsVisible functionality
	$effect(() => {
		if (processingState && isMonitoring) {
			lastKnownState = processingState;
		}
	});

	// Update EMA whenever the server reports a new predicted_per_second
	$effect(() => {
		const tps = processingState?.tokensPerSecond ?? 0;
		const n   = processingState?.tokensDecoded  ?? 0;
		if (n === 0) {
			smoothedTps = 0;  // reset between responses
		} else if (tps > 0 && n > 1) {
			// Skip n=1: first token always has near-zero predicted_ms → 1M t/s spike
			smoothedTps = smoothedTps === 0 ? tps : 0.25 * tps + 0.75 * smoothedTps;
		}
	});

	// Track last known processing stats for when promptProgress disappears
	$effect(() => {
		if (processingState?.promptProgress) {
			const { processed, total, time_ms, cache } = processingState.promptProgress;
			const actualProcessed = processed - cache;
			const actualTotal = total - cache;

			if (actualProcessed > 0 && time_ms > 0) {
				const tokensPerSecond = actualProcessed / (time_ms / 1000);
				lastKnownProcessingStats = {
					tokensProcessed: actualProcessed,
					totalTokens: actualTotal,
					timeMs: time_ms,
					tokensPerSecond
				};
			}
		}
	});

	function getETASecs(done: number, total: number, elapsedMs: number): number | undefined {
		const elapsedSecs = elapsedMs / 1000;
		const progressETASecs =
			done === 0 || elapsedSecs < 0.5
				? undefined // can be the case for the 0% progress report
				: elapsedSecs * (total / done - 1);
		return progressETASecs;
	}

	function startMonitoring(): void {
		if (isMonitoring) return;
		isMonitoring = true;
	}

	function stopMonitoring(): void {
		if (!isMonitoring) return;
		isMonitoring = false;

		// Only clear last known state if keepStatsVisible is disabled
		const currentConfig = config();
		if (!currentConfig.keepStatsVisible) {
			lastKnownState = null;
			lastKnownProcessingStats = null;
		}
	}

	function getProcessingMessage(): string {
		if (!processingState) {
			return 'Processing...';
		}

		switch (processingState.status) {
			case 'initializing':
				return 'Initializing...';
			case 'preparing':
				if (processingState.progressPercent !== undefined) {
					return `Processing (${processingState.progressPercent}%)`;
				}
				return 'Preparing response...';
			case 'generating':
				return '';
			default:
				return 'Processing...';
		}
	}

	function getProcessingDetails(): string[] {
		// Use current processing state or fall back to last known state
		const stateToUse = processingState || lastKnownState;
		if (!stateToUse) {
			return [];
		}

		const details: string[] = [];

		// Show prompt processing progress with ETA during preparation phase
		if (stateToUse.promptProgress) {
			const { processed, total, time_ms, cache } = stateToUse.promptProgress;
			const actualProcessed = processed - cache;
			const actualTotal = total - cache;

			if (actualProcessed < actualTotal && actualProcessed > 0) {
				const percent = Math.round((actualProcessed / actualTotal) * 100);
				const eta = getETASecs(actualProcessed, actualTotal, time_ms);

				if (eta !== undefined) {
					const etaSecs = Math.ceil(eta);
					details.push(`Processing ${percent}% (ETA: ${etaSecs}s)`);
				} else {
					details.push(`Processing ${percent}%`);
				}
			}
		}

		// Always show context info when we have valid data
		if (
			typeof stateToUse.contextTotal === 'number' &&
			stateToUse.contextUsed >= 0 &&
			stateToUse.contextTotal > 0
		) {
			const contextPercent = Math.round((stateToUse.contextUsed / stateToUse.contextTotal) * 100);

			details.push(
				`Context: ${stateToUse.contextUsed}/${stateToUse.contextTotal} (${contextPercent}%)`
			);
		}

		if (stateToUse.outputTokensUsed > 0) {
			// Handle infinite max_tokens (-1) case
			if (stateToUse.outputTokensMax <= 0) {
				details.push(`Output: ${stateToUse.outputTokensUsed}/∞`);
			} else {
				const outputPercent = Math.round(
					(stateToUse.outputTokensUsed / stateToUse.outputTokensMax) * 100
				);

				details.push(
					`Output: ${stateToUse.outputTokensUsed}/${stateToUse.outputTokensMax} (${outputPercent}%)`
				);
			}
		}

		if (stateToUse.tokensPerSecond && stateToUse.tokensPerSecond > 0) {
			details.push(`${stateToUse.tokensPerSecond.toFixed(1)} ${STATS_UNITS.TOKENS_PER_SECOND}`);
		}

		if (stateToUse.speculative) {
			details.push('Speculative decoding enabled');
		}

		return details;
	}

	/**
	 * Returns technical details without the progress message (for bottom bar)
	 */
	function getTechnicalDetails(): string[] {
		const stateToUse = processingState || lastKnownState;
		if (!stateToUse) {
			return [];
		}

		const details: string[] = [];

		// Always show context info when we have valid data
		if (
			typeof stateToUse.contextTotal === 'number' &&
			stateToUse.contextUsed >= 0 &&
			stateToUse.contextTotal > 0
		) {
			const contextPercent = Math.round((stateToUse.contextUsed / stateToUse.contextTotal) * 100);

			details.push(
				`Context: ${stateToUse.contextUsed}/${stateToUse.contextTotal} (${contextPercent}%)`
			);
		}

		if (stateToUse.outputTokensUsed > 0) {
			// Handle infinite max_tokens (-1) case
			if (stateToUse.outputTokensMax <= 0) {
				details.push(`Output: ${stateToUse.outputTokensUsed}/∞`);
			} else {
				const outputPercent = Math.round(
					(stateToUse.outputTokensUsed / stateToUse.outputTokensMax) * 100
				);

				details.push(
					`Output: ${stateToUse.outputTokensUsed}/${stateToUse.outputTokensMax} (${outputPercent}%)`
				);
			}
		}

		if (stateToUse.tokensPerSecond && stateToUse.tokensPerSecond > 0) {
			details.push(`${stateToUse.tokensPerSecond.toFixed(1)} ${STATS_UNITS.TOKENS_PER_SECOND}`);
		}

		if (stateToUse.speculative) {
			details.push('Speculative decoding enabled');
		}

		return details;
	}

	function shouldShowDetails(): boolean {
		return processingState !== null && processingState.status !== 'idle';
	}

	/**
	 * Returns a short progress message with percent
	 */
	function getPromptProgressText(): string | null {
		if (!processingState?.promptProgress) return null;

		const { processed, total, cache } = processingState.promptProgress;

		const actualProcessed = processed - cache;
		const actualTotal = total - cache;
		const percent = Math.round((actualProcessed / actualTotal) * 100);
		const eta = getETASecs(actualProcessed, actualTotal, processingState.promptProgress.time_ms);

		if (eta !== undefined) {
			const etaSecs = Math.ceil(eta);
			return `Processing ${percent}% (ETA: ${etaSecs}s)`;
		}

		return `Processing ${percent}%`;
	}

	/**
	 * Returns live processing statistics for display (prompt processing phase)
	 * Returns last known stats when promptProgress becomes unavailable
	 */
	function getLiveProcessingStats(): LiveProcessingStats | null {
		if (processingState?.promptProgress) {
			const { processed, total, time_ms, cache } = processingState.promptProgress;

			const actualProcessed = processed - cache;
			const actualTotal = total - cache;

			if (actualProcessed > 0 && time_ms > 0) {
				const tokensPerSecond = actualProcessed / (time_ms / 1000);

				return {
					tokensProcessed: actualProcessed,
					totalTokens: actualTotal,
					timeMs: time_ms,
					tokensPerSecond
				};
			}
		}

		// Return last known stats if promptProgress is no longer available
		return lastKnownProcessingStats;
	}

	/**
	 * Returns live generation statistics for display (token generation phase).
	 * Uses EMA-smoothed t/s so OS-scheduler jitter doesn't tank the number.
	 */
	function getLiveGenerationStats(): LiveGenerationStats | null {
		if (!processingState) return null;

		const { tokensDecoded } = processingState;
		if (tokensDecoded <= 0) return null;

		// Use smoothed value; fall back to raw only if smoothing hasn't kicked in yet
		const displayTps = smoothedTps > 0 ? smoothedTps : (processingState.tokensPerSecond || 0);
		const timeMs     = displayTps > 0 ? (tokensDecoded / displayTps) * 1000 : 0;

		return {
			tokensGenerated: tokensDecoded,
			timeMs,
			tokensPerSecond: displayTps
		};
	}

	return {
		get processingState() {
			return processingState;
		},
		getProcessingDetails,
		getTechnicalDetails,
		getProcessingMessage,
		getPromptProgressText,
		getLiveProcessingStats,
		getLiveGenerationStats,
		shouldShowDetails,
		startMonitoring,
		stopMonitoring
	};
}
