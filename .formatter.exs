export_locals_without_parens = [plug: 1, plug: 2]

[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  locals_without_parens: export_locals_without_parens,
  export: [
    locals_without_parens: export_locals_without_parens
  ]
]
