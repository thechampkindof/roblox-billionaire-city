--!strict
--[[
	`ProfileProvider` interface — the *only* place that talks to a backing store.

	Swap-in instructions for production (documented in docs/DECISIONS.md):
	  * implement this interface with ProfileStore (MadStudio/loleris),
	  * set `DataService.providerFactory` to return it,
	  * keep session locking + autosave in `DataService` unchanged.
	Nothing else in the codebase may require DataStoreService.
]]

export type LoadOk = {
	-- The raw saved profile, or `nil` for a brand-new player.
	data: any?,
	sessionKey: string,
	-- true when this load created a fresh profile (no save existed).
	fresh: boolean,
}

export type ProfileProviderImpl = {
	Name: string,
	--[[ Returns Result<LoadOk>; fails when another live session holds the lock. ]]
	LoadAsync: (self: ProfileProviderImpl, userId: number) -> any,
	--[[ Returns Result<boolean>; fails when this session no longer owns the lock. ]]
	SaveAsync: (self: ProfileProviderImpl, userId: number, data: any, sessionKey: string) -> any,
	--[[ Best-effort lock release; never throws. ]]
	ReleaseAsync: (self: ProfileProviderImpl, userId: number, sessionKey: string) -> (),
}

return {}
