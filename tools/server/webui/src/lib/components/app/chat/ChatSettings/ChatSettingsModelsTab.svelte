<script lang="ts">
	import { onMount, onDestroy } from 'svelte';
	import { Loader2, PackageOpen, HardDrive } from '@lucide/svelte';
	import { serverStore } from '$lib/stores/server.svelte';

	const MCP = 'http://localhost:8808';

	interface ModelEntry {
		path: string;
		name: string;
		folder: string;
		size_mb: number;
	}

	let models = $state<ModelEntry[]>([]);
	let current = $state<string | null>(null);
	let serverReady = $state(false);
	let switching = $state<string | null>(null);
	let pollTimer: ReturnType<typeof setInterval> | null = null;
	let mcpError = $state(false);

	function fmt(mb: number): string {
		return mb >= 1000 ? `${(mb / 1024).toFixed(1)} GB` : `${mb.toFixed(0)} MB`;
	}

	async function loadModels() {
		try {
			const r = await fetch(`${MCP}/models`);
			if (r.ok) {
				models = await r.json();
				mcpError = false;
			}
		} catch {
			mcpError = true;
		}
	}

	async function pollCurrent() {
		try {
			const r = await fetch(`${MCP}/current`, { cache: 'no-store' });
			if (r.ok) {
				const d = await r.json();
				serverReady = d.ready;
				current = d.model ?? null;
				mcpError = false;
				if (switching && d.ready && d.model === switching) {
					switching = null;
					serverStore.fetch();
				}
			}
		} catch {
			serverReady = false;
			current = null;
		}
	}

	async function doUnload() {
		if (switching) return;
		switching = '__unloading__';
		try {
			await fetch(`${MCP}/unload`, { method: 'POST' });
		} catch {}
		switching = null;
		await pollCurrent();
		serverStore.fetch();
	}

	async function doSwitch(entry: ModelEntry) {
		if (switching) return;
		switching = entry.name;
		try {
			await fetch(`${MCP}/switch`, {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({ model_path: entry.path })
			});
		} catch {}
	}

	onMount(() => {
		loadModels();
		pollCurrent();
		pollTimer = setInterval(pollCurrent, 1500);
	});

	onDestroy(() => {
		if (pollTimer) clearInterval(pollTimer);
	});

	let grouped = $derived.by(() => {
		const map = new Map<string, ModelEntry[]>();
		for (const m of models) {
			const key = m.folder || '(root)';
			if (!map.has(key)) map.set(key, []);
			map.get(key)!.push(m);
		}
		return map;
	});
</script>

<div class="space-y-4">
	<!-- Status bar -->
	<div class="flex items-center gap-2 rounded-lg border border-border/40 bg-muted/30 px-3 py-2.5 text-sm">
		{#if switching === '__unloading__'}
			<Loader2 class="h-3.5 w-3.5 shrink-0 animate-spin text-amber-500" />
			<span class="text-muted-foreground">Unloading model…</span>
		{:else if switching}
			<Loader2 class="h-3.5 w-3.5 shrink-0 animate-spin text-amber-500" />
			<span class="text-muted-foreground">Loading <span class="font-medium text-foreground">{switching}</span>…</span>
		{:else if serverReady && current}
			<span class="h-2 w-2 shrink-0 rounded-full bg-green-500"></span>
			<span class="text-muted-foreground">Running: <span class="font-medium text-foreground">{current}</span></span>
		{:else if serverReady}
			<span class="h-2 w-2 shrink-0 rounded-full bg-green-500"></span>
			<span class="text-muted-foreground">Server ready</span>
		{:else}
			<span class="h-2 w-2 shrink-0 rounded-full bg-red-500"></span>
			<span class="text-muted-foreground">llama-server offline</span>
		{/if}
	</div>

	{#if mcpError}
		<div class="rounded-lg border border-destructive/30 bg-destructive/10 px-3 py-2.5 text-xs text-destructive">
			Cannot reach MCP server on port 8808. Make sure you launched with <code class="font-mono">./start-up.sh</code>.
		</div>
	{/if}

	<!-- Model list -->
	{#if models.length === 0 && !mcpError}
		<div class="py-6 text-center text-sm text-muted-foreground">
			<PackageOpen class="mx-auto mb-2 h-8 w-8 opacity-30" />
			Scanning for models…
		</div>
	{:else}
		<div class="space-y-3">
			{#each [...grouped.entries()] as [folder, entries]}
				<div>
					<div class="mb-1.5 flex items-center gap-1.5 text-[10px] font-semibold uppercase tracking-widest text-muted-foreground/60">
						<HardDrive class="h-3 w-3" />
						{folder}
					</div>
					<div class="space-y-0.5 rounded-lg border border-border/30 overflow-hidden">
						{#each entries as entry}
							{@const isCurrent = entry.name === current}
							{@const isLoading = entry.name === switching}
							<div
								class="flex items-center gap-3 px-3 py-2.5 text-sm transition-colors
									{isCurrent ? 'bg-green-500/10' : 'hover:bg-muted/40'}
									{!isCurrent && !isLoading ? 'cursor-default' : ''}"
							>
								<span
									class="flex-1 truncate font-medium
										{isCurrent ? 'text-green-400' : 'text-foreground'}"
									title={entry.name}
								>
									{entry.name}
								</span>
								<span class="shrink-0 text-xs text-muted-foreground">{fmt(entry.size_mb)}</span>

								{#if isCurrent}
									<span class="shrink-0 rounded-full bg-green-500/20 px-2 py-0.5 text-[11px] font-semibold text-green-400">
										Loaded
									</span>
									<button
										class="shrink-0 rounded-md border border-red-500/30 px-3 py-1 text-xs font-semibold text-red-400
											hover:border-red-500 hover:bg-red-500/10 disabled:cursor-not-allowed disabled:opacity-40"
										disabled={!!switching}
										onclick={doUnload}
									>
										Unload
									</button>
								{:else if isLoading}
									<span class="flex shrink-0 items-center gap-1 text-xs text-amber-400">
										<Loader2 class="h-3 w-3 animate-spin" />
										Loading…
									</span>
								{:else}
									<button
										class="shrink-0 rounded-md bg-primary px-3 py-1 text-xs font-semibold text-primary-foreground
											hover:bg-primary/90 disabled:cursor-not-allowed disabled:opacity-40"
										disabled={!!switching || !serverReady}
										onclick={() => doSwitch(entry)}
									>
										Load
									</button>
								{/if}
							</div>
						{/each}
					</div>
				</div>
			{/each}
		</div>
	{/if}

	<p class="text-[11px] text-muted-foreground/50">
		Models scanned from <code class="font-mono">~/.lmstudio/models</code>.
		Loading a model unloads the current one and restarts the server.
	</p>
</div>
