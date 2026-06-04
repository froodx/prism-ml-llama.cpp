<script lang="ts">
	import { ChevronDown, ChevronUp, Activity } from '@lucide/svelte';

	interface SpeedEntry {
		ts: number;        // unix ms
		model: string;
		tokens: number;
		tps: number;       // predicted_per_second from server (accurate)
		promptTokens: number;
		promptTps: number;
	}

	const MAX_ENTRIES = 50;
	const STORAGE_KEY = 'bonsai_speed_log';

	let expanded = $state(false);
	let entries = $state<SpeedEntry[]>(loadLog());

	function loadLog(): SpeedEntry[] {
		try {
			const raw = sessionStorage.getItem(STORAGE_KEY);
			return raw ? JSON.parse(raw) : [];
		} catch { return []; }
	}

	function saveLog(log: SpeedEntry[]) {
		try { sessionStorage.setItem(STORAGE_KEY, JSON.stringify(log)); } catch {}
	}

	export function record(entry: Omit<SpeedEntry, 'ts'>) {
		if (!entry.tps || entry.tps <= 0 || !entry.tokens) return;
		const next = [{ ...entry, ts: Date.now() }, ...entries].slice(0, MAX_ENTRIES);
		entries = next;
		saveLog(next);
	}

	export function clear() {
		entries = [];
		saveLog([]);
	}

	function fmt(n: number, dec = 1) { return n.toFixed(dec); }
	function fmtTime(ts: number) {
		return new Date(ts).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' });
	}

	let avgTps = $derived.by(() => {
		if (!entries.length) return 0;
		return entries.reduce((s, e) => s + e.tps, 0) / entries.length;
	});

	let peakTps = $derived(entries.length ? Math.max(...entries.map(e => e.tps)) : 0);
</script>

{#if entries.length > 0}
<div class="mt-1 text-xs text-muted-foreground">
	<button
		class="flex items-center gap-1 hover:text-foreground transition-colors"
		onclick={() => (expanded = !expanded)}
	>
		<Activity class="h-3 w-3" />
		<span>Speed log · avg {fmt(avgTps)} t/s · peak {fmt(peakTps)} t/s</span>
		{#if expanded}
			<ChevronUp class="h-3 w-3" />
		{:else}
			<ChevronDown class="h-3 w-3" />
		{/if}
	</button>

	{#if expanded}
		<div class="mt-1 rounded-lg border border-border/30 bg-muted/20 overflow-hidden">
			<table class="w-full text-[11px]">
				<thead>
					<tr class="border-b border-border/30 text-muted-foreground/70">
						<th class="px-2 py-1 text-left font-medium">Time</th>
						<th class="px-2 py-1 text-left font-medium">Model</th>
						<th class="px-2 py-1 text-right font-medium">Tokens</th>
						<th class="px-2 py-1 text-right font-medium">Gen t/s</th>
						<th class="px-2 py-1 text-right font-medium">Prompt t/s</th>
					</tr>
				</thead>
				<tbody>
					{#each entries as e}
						<tr class="border-b border-border/20 last:border-0 hover:bg-muted/30 transition-colors">
							<td class="px-2 py-1 text-muted-foreground/60">{fmtTime(e.ts)}</td>
							<td class="px-2 py-1 max-w-[10rem] truncate" title={e.model}>{e.model}</td>
							<td class="px-2 py-1 text-right">{e.tokens}</td>
							<td class="px-2 py-1 text-right font-mono
								{e.tps > 80 ? 'text-green-400' : e.tps > 40 ? 'text-amber-400' : 'text-red-400'}">
								{fmt(e.tps)}
							</td>
							<td class="px-2 py-1 text-right font-mono text-muted-foreground">
								{e.promptTps > 0 ? fmt(e.promptTps) : '—'}
							</td>
						</tr>
					{/each}
				</tbody>
			</table>
			<div class="flex justify-end px-2 py-1 border-t border-border/20">
				<button class="text-[10px] text-muted-foreground/50 hover:text-muted-foreground" onclick={clear}>
					Clear log
				</button>
			</div>
		</div>
	{/if}
</div>
{/if}
