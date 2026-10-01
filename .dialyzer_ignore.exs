[
  # Known false positive: Dialyzer can't see through Ecto.Multi's opaque
  # struct across `Ecto.Multi.new() |> Ecto.Multi.update(:user, changeset)`
  # pipelines. Reproduces on stock `mix phx.gen.auth` output (the four
  # sites in accounts.ex that update a user inside a multi alongside
  # deleting their old tokens), not something this app's own code
  # caused. Confirmed by trying both pipe and bind forms.
  {"lib/tally/accounts.ex", :call_without_opaque},

  # Same opaque-Ecto.Multi false positive as above, this time on
  # `Ecto.Multi.insert_all/4` in Finance.run_import/4's bulk-insert +
  # import-status-update pipeline.
  {"lib/tally/finance.ex", :call_without_opaque}
]
