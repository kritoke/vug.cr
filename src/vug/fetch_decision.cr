module Vug
  # A loop-control decision made by the fetch loop after each round-trip.
  #
  # Replaces the `{LoopAction, String?, URI?}` 3-tuple that the loop
  # used to return from its dispatch helpers. The tuple was easy to
  # misorder, and the third element silently flipped between
  # `current_uri` (pass-through) and `nil` (force re-parse) depending
  # on the action — a hidden side-channel the caller had to know about.
  #
  # `reparse: true` is set when the loop should drop its cached
  # `LoopState#current_uri` so the next iteration re-parses from the
  # (possibly new) `state.current_url`. The other fields carry the
  # action and the optional next URL exactly as before.
  record FetchDecision, action : LoopAction, next_url : String?, reparse : Bool
end
