[
  # Known false positive: Dialyzer can't see through Ecto.Multi's opaque
  # struct across `Ecto.Multi.new() |> Ecto.Multi.update(:user, changeset)`
  # pipelines. Reproduces on stock `mix phx.gen.auth` output (the four
  # sites in accounts.ex that update a user inside a multi alongside
  # deleting their old tokens), not something this app's own code
  # caused. Confirmed by trying both pipe and bind forms.
  {"lib/tally/accounts.ex", :call_without_opaque}
]
