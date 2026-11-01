# JSON host API

CLI: `node scripts/cli.mjs request.json [--out new-result.json]`, or `-` for UTF-8 stdin. Output creation uses exclusive mode and refuses to overwrite an existing file. Exit codes: 0 successful computation, 2 model/request error, 1 host IO error, 64 invalid CLI arguments.

Request fields:

| Field | Meaning |
| --- | --- |
| model.events | Array of `{id, probability}` |
| model.gates | Array of `{id, kind, inputs}`; kind and/or/vote; vote also needs threshold |
| model.top | Event or gate ID |
| order | Optional complete event-ID permutation |
| overrides | Optional event-ID → probability map |
| forced | Optional event-ID → Boolean state map |
| max_cut_sets | Default 5000; 1..5000 intermediate antichain bound |
| command | analyze (default) or probability |

`analyze` returns `{ok:true,result:{probability,importance,minimal_cut_sets,cut_union_bound,bdd_nodes,basic_events}}`. `probability` returns `{ok:true,result:number}`. Errors are `{ok:false,code:"invalid"|"limit"|"json",error:string}`. Requests are limited to 1,000,000 UTF-16 units. No URLs, source files, arbitrary expressions or host commands are executed.

See the three examples for full requests. The same input string can be passed to the public MoonBit `run_json` function or the compiled `run_json` export.
