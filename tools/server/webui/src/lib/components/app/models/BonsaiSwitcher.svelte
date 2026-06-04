<script lang="ts">
	import { onMount, onDestroy } from 'svelte';
	import { ChevronDown, Loader2, PackageOpen } from '@lucide/svelte';
	import * as DropdownMenu from '$lib/components/ui/dropdown-menu';
	import { Button } from '$lib/components/ui/button';
	import { serverStore } from '$lib/stores/server.svelte';

	// MCP server is always localhost:8808 (same machine as the model runner)
	const MCP = 'http://localhost:8808';

	interface ModelEntry {
		path: string;
		name: string;
		folder: string;
		size_mb: number;
	}

	let models = $state<ModelEntry[]>([]);
	let current = $state<string | null>(null);
	let switching = $state<string | null>(null);
	let open = $state(false);
	let pollTimer: ReturnType<typeof setInterval> | null = null;

	function fmt(mb: number): string {
		return mb >= 1000 ? `${(mb / 1024).toFixed(1)} GB` : `${mb.toFixed(0)} MB`;
	}

	async function loadModels() {
		try {
			const r = await fetch(`${MCP}/models`);
			if (r.ok) models = await r.json();
		} catch {}
	}

	async function pollCurrent() {
		try {
			const r = await fetch(`${MCP}/current`, { cache: 'no-store' });
			if (r.ok) {
				const d = await r.json();
				current = d.model ?? null;
				// If the server came back with the model we were switching to, done
				if (switching && d.ready && d.model === switching) {
					switching = null;
					// Nudge the server store to re-fetch props so the rest of the UI updates
					serverStore.fetchServerData();
				}
			}
		} catch {
			current = null;
		}
	}

	async function switchModel(entry: ModelEntry) {
		if (switching) return;
		switching = entry.name;
		open = false;
		try {
			await fetch(`${MCP}/switch`, {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({ model_path: entry.path })
			});
		} catch {}
		// Polling will detect when it's ready and clear `switching`
	}

	onMount(() => {
		loadModels();
		pollCurrent();
		pollTimer = setInterval(pollCurrent, 1500);
	});

	onDestroy(() => {
		if (pollTimer) clearInterval(pollTimer);
	});

	// Group models by folder
	let grouped = $derived.by(() => {
		const map = new Map<string, ModelEntry[]>();
		for (const m of models) {
			const key = m.folder || '(root)';
			if (!map.has(key)) map.set(key, []);
			map.get(key)!.push(m);
		}
		return map;
	});

	let displayName = $derived(switching ?? current ?? '…');
</script>

<DropdownMenu.Root bind:open>
	<DropdownMenu.Trigger asChild let:builder>
		<Button
			builders={[builder]}
			variant="ghost"
			size="sm"
			class="h-7 max-w-[14rem] gap-1 truncate px-2 text-xs font-medium text-muted-foreground hover:text-foreground"
			title={switching ? `Loading ${switching}…` : (current ?? 'Switch model')}
		>
			{#if switching}
				<Loader2 class="h-3 w-3 shrink-0 animate-spin" />
			{:else}
				<PackageOpen class="h-3 w-3 shrink-0" />
			{/if}
			<span class="truncate">{displayName}</span>
			{#if !switching}
				<ChevronDown class="h-3 w-3 shrink-0 opacity-50" />
			{/if}
		</Button>
	</DropdownMenu.Trigger>

	<DropdownMenu.Content class="w-80" align="end" sideOffset={6}>
		<div class="px-2 py-1.5 text-[10px] font-semibold uppercase tracking-widest text-muted-foreground">
			Switch Model
		</div>
		<DropdownMenu.Separator />

		{#if models.length === 0}
			<div class="px-3 py-4 text-center text-xs text-muted-foreground">
				No models found — is the MCP server running?
			</div>
		{:else}
			{#each [...grouped.entries()] as [folder, entries]}
				<div class="px-2 pt-2 pb-0.5 text-[10px] font-semibold uppercase tracking-wider text-muted-foreground/60">
					{folder}
				</div>
				{#each entries as entry}
					<DropdownMenu.Item
						class="flex cursor-pointer items-center gap-2 rounded-sm px-2 py-1.5 text-xs"
						disabled={!!switching || entry.name === current}
						onclick={() => switchModel(entry)}
					>
						<span class="flex-1 truncate" class:font-semibold={entry.name === current}>
							{entry.name}
						</span>
						<span class="shrink-0 text-muted-foreground">{fmt(entry.size_mb)}</span>
						{#if entry.name === current}
							<span class="shrink-0 text-green-500">✓</span>
						{/if}
					</DropdownMenu.Item>
				{/each}
			{/each}
		{/if}

		<DropdownMenu.Separator />
		<div class="px-3 py-1.5 text-[10px] text-muted-foreground/50">
			Full switcher: <a href="http://{window.location.hostname}:8808" target="_blank" class="underline">localhost:8808</a>
		</div>
	</DropdownMenu.Content>
</DropdownMenu.Root>
