module Vug
  # Type-safe action enum replacing bare Symbol dispatch in the fetch loop.
  #
  # Named `LoopAction` to disambiguate from `FetchAction` (the redirect
  # handler's Follow/Deny decision in `fetch_types.cr`). The two are
  # different concepts: `LoopAction` is a loop-control decision made by
  # the fetch loop after each round-trip; `FetchAction` is a single
  # per-redirect decision made by the redirect validator.
  enum LoopAction
    Redirect
    TryFallback
    ReturnResult
    UseCached
  end
end
