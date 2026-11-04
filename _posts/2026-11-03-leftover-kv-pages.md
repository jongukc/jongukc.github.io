---
layout: post
title: "KV cache safety: other users' prompts in your answer"
description: "Cloudflare's GLM-5.3 KV cache exposure explained as an uninitialized KV read, and how KVGuard catches it."
date: 2026-11-03
author:
  - "Jonguk Cheong"
published: false
---

<!-- What went wrong in Cloudflare's GLM-5.3 KV cache incident, and why one generic check catches this whole class of bug, whichever code path triggers it. -->

## In short

- **What happened.** An SGLang serving bug made a request read KV cache blocks
  it never wrote. Those blocks still held other users' data, which leaked into
  155 answers.
- **Why tools missed it.** Sanitizers see the KV cache as one valid,
  already-written GPU buffer. The bug only exists at the level of KV blocks and
  requests, so nothing crashed and nothing was flagged.
- **Why the fix is limited.** Cloudflare's four shipped fixes each close one
  trigger: the pool size, the rejection path, the release timing, and the
  transfer. Cloudflare says so itself. It calls the transfer checksum "a first
  step" and names a check on _every read_ as the real goal.
- **What KVGuard adds.** That every-read check, built as a general design. A
  request may read only entries it wrote, in blocks it owns. Tracking which
  entries were _written_, not just who owns a page, is what this incident needs.

## What happened

In October 2026, Cloudflare
[disclosed](https://blog.cloudflare.com/kv-cache-exposure-remediation/) that
155 responses from the GLM-5.3 model on Workers AI contained pieces of _other
users'_ prompts and outputs. The affected responses were served between August
27 and September 9, and every one of them came from a prompt longer than
681,280 tokens. No alarm went off. A security researcher noticed foreign text
in their own responses and reported it through HackerOne. Cloudflare took the
model private, found the root cause, and restored the model with fixes on the
same day.

The model itself was not wrong. The leak came from how the serving system,
SGLang, manages the GPU memory that holds the **KV cache**.

## The KV cache in one paragraph

While an LLM reads a prompt, it stores keys and values (KV) for every token so
it does not recompute them for each new output token. Serving engines such as
vLLM and SGLang keep this KV cache in one large GPU buffer that is split into
fixed-size **physical blocks** (pages). Each request has a **block table** that
maps its logical blocks to physical ones. When a request finishes, its blocks
go back to the pool and the next request simply overwrites them. Blocks are
_not_ zeroed between requests. This is safe only if a request never reads a
block entry it has not written itself.

## The incident in five steps

Cloudflare runs GLM-5.3 with prefill/decode disaggregation. Prefill GPUs
process the prompt and send its KV cache over RDMA to decode GPUs, which
generate the answer. Two problems lined up. The advertised context window was
1,048,576 tokens, but the prefill KV pool held only 681,280 tokens. And an
SGLang bug let a request that was rejected for being too long keep going as if
it were alive.

![Diagram: prefill GPU rejects an oversized request but sends one KV page;
decode GPU reserved eight pages and attention reads all of them, including
seven stale pages from other
users.](/assets/figs/leftover-kv-pages/fig1-incident.svg)

**Figure 1.** The Cloudflare incident: a rejected over-length request still
reaches decode, and attention reads seven reserved blocks it never wrote that
still hold other users' KV.

1.  The decode GPU reserves 8 KV blocks for the request, sized for its full
    prompt.

2.  Prefill sees that the prompt does not fit in its KV pool and rejects it.
    But the check asked whether the request had `finished()`, not whether it
    was `rejected()`, so the rejected request still looked alive.

3.  Prefill runs a one-token placeholder instead of the real prompt and
    produces just one KV block.

4.  Prefill sends that one block to decode and reports the transfer as
    complete. Decode accepts it without checking that all 8 blocks arrived.

5.  Decode starts generating. Attention reads all 8 reserved blocks. Only PB0
    was written by this request. PB1–PB7 still hold other users' prompts and
    partial generations, and the model's answer is built on top of them.

Nothing crashed and nothing raised an error. The system served a fluent answer
that happened to contain someone else's data.

## A known class of bug: the uninitialized KV read

In the KVGuard paper we study memory-safety bugs in the KV cache. Because
engines manage KV blocks with their own allocator on top of one big GPU buffer,
they inherit the classic memory-safety bug classes, one level up:

- double-free
- use-after-free
- out-of-bounds access
- **uninitialized read**
- permission violation

The Cloudflare incident is an **uninitialized read**: a request reads KV
entries it never wrote, so it sees whatever the previous owner left there. The
paper's Case 3 (bug B6 in its table) has the same shape in vLLM: a restore from
CPU offload assigns two blocks to a request, counts both as computed, and loads
only one. The request then reads the other, and the prefix cache can share it
onward. All five classes share one dangerous trait. They rarely crash. They
show up as slightly wrong output, or, as here, as another request's data.

## Why existing tools miss it

This leak ran for almost two weeks, and no test, monitor, or tool caught it. A
person reading the output did. Cloudflare's post shows how healthy everything
looked:

> “During pre-launch testing we observed successful HTTP status codes and a
> streaming body with no error frames during benchmarking.”

Every signal the system had said "fine": HTTP 200, normal streaming, and no
errors. The only clue was the meaning of the text, and only the user who
received it could tell it belonged to someone else. Once the report arrived,
Cloudflare reproduced the leak with two accounts in 25 minutes. Finding it took
a human. Every standard defense was looking at the wrong level:

- **CPU sanitizers** such as AddressSanitizer never see GPU memory, and the bad
  read happens inside a CUDA attention kernel.

- **GPU sanitizers** see CUDA allocations, not KV blocks. The engine allocates
  the whole KV cache as one big buffer at startup. To NVIDIA Compute Sanitizer's
  `memcheck`, reading PB1 is an in-bounds access to a valid buffer. To its
  `initcheck`, PB1 was written long ago by an earlier request, so it counts as
  initialized. The bug only exists at the level of blocks, requests, and block
  tables, which these tools do not know about. They are also too slow to sit in a
  pre-launch test. In our measurements `memcheck` slows serving by 72 to 262
  times, and `initcheck` as shipped buries the log in reports from PyTorch
  kernels that never touch the KV cache.

- **Crashes and error checks** never trigger. Stale KV is well-formed data.
  Attention computes over it normally and the model writes a fluent answer.

- **Load tests and benchmarks** pass, as Cloudflare's did. They check status
  codes and throughput, not whether the text came from this request's own
  context.

## How KVGuard catches it

KVGuard keeps a small **shadow block** for every physical KV block. A shadow
block records two things: which request may access the block (_permission_),
and which entries in it have been written in the block's current lifetime
(_initialization_). When a block is allocated to a request, its init bits are
cleared. A write sets them. Before every KV read in the attention kernel,
KVGuard checks that the entry's init bit is set (check C5 in the paper).

![Diagram: KVGuard shadow blocks under each KV block. PB0 is initialized, PB1
to PB7 are not. The C5 check on the attention read fires on
PB1.](/assets/figs/leftover-kv-pages/fig2-kvguard-check.svg)

**Figure 2.** The same decode step under KVGuard: every block's permission
passes, but only PB0 is marked written, so C5 fires on the first read of PB1.

In this incident, PB1–PB7 really were allocated to the request, so a permission
check alone would pass. The init bits tell a different story. When decode
reserved the blocks, their bits were cleared; the transfer wrote only one
entry, in PB0. The first time attention touches PB1, C5 fires and names the
request, the block, and the entry.

The transfer itself is checked: as a read on the sender, whose source entries
must already be initialized, and as a write on the receiver, whose destination
entries become initialized only for what the transfer actually delivers (§4.4).
The receiver cannot tell a short delivery from a full one on its own, since
both finish the same way, so the sender passes the count of entries it wrote,
and the receiver marks only those entries initialized. That count is the one
piece of metadata KVGuard adds; each node still checks against its own shadow
blocks. Had the sender instead tried to send eight blocks it never wrote, C5
would have fired on the sender, at submission.

This is not only a design argument. We reproduced the incident on SGLang
0.5.19, the last release before the upstream fix, with a prefill node and a
decode node on one GPU and KVGuard attached to both. The prefill node rejects
the over-length prompt, swaps in a one-token placeholder, and the decode node —
which reserved 256 pages for the full prompt while the transfer delivered one —
serves a normal HTTP 200 answer, the incident's signature. KVGuard marks only
the one delivered page initialized, so the first decode step's reads of the
other 255 trip C5: **4,095 uninitialized reads on that one request**, each
naming the request, the block, and the entry, at the exact read where another
user's data would enter the answer. A normal request transfers in full, and
KVGuard stays silent.

Take away that count and KVGuard goes as blind as the engine: it assumes the
whole reservation was written. With it, the check needs no knowledge of _why_ a
transfer fell short, only that it did, so the same report stands whether the
short delivery came from this rejection bug or from any other path.

## Point fixes vs. one invariant

Cloudflare responded quickly and thoroughly. Look at what each fix protects,
though. Every one of them names a specific trigger or a specific boundary.

| Fix                                                           | What it prevents                                                           |
| ------------------------------------------------------------- | -------------------------------------------------------------------------- |
| KV pool resized to about 2× the context length                | Prompts larger than this deployment's pool                                 |
| Retire rejected requests at admission (SGLang #36988, #38935) | A rejected request reaching decode                                         |
| Deferred KV release by default (#37454, #41023)               | KV freed while a transfer is still in flight                               |
| KV checksum on the prefill-to-decode handoff (#39500)         | Corrupted data in the transfer                                             |
| **KVGuard check C5**                                          | **Any read of a KV entry its request has not written, from any code path** |

Each of these fixes is right, and production systems need them. But each one is
tied to how this particular leak happened. The same leak could come back by a
different route: a preempted request that resumes with part of its KV missing,
a prefix-cache bookkeeping slip, or a kernel that rounds a partial block up.
None of the four fixes is about those routes.

This is not hypothetical. Of the 29 historical bugs in our paper's table, eight
are uninitialized reads, seven of them in SGLang, and each arrived by its own
path. In B6, vLLM's restore from CPU offload counts a block as loaded that it
never filled, the Case 3 above. In B21, SGLang's prefill side sends a cached
prefix to the decode side before the HiCache load that fills it has landed,
under EAGLE3 and disaggregation. In B15, SGLang's mixed chunked prefill under
the overlap scheduler loses a chunk's recurrent-state write, and a later state
copy reads a slot nothing wrote. In N3, which KVGuard found, SGLang quantizes a
short request's never-written state slot into an int8 checkpoint. SGLang's
prefill/decode path alone accounts for three entries in the table: B21, N4, in
which parallel samples of one request share one transfer and one sample's KV
lands in another's blocks, and N7, in which an aborted prefill frees its KV
while the transfer is still reading it. Each historical one was fixed with its
own patch after someone noticed something wrong; the new ones have fix pull
requests open.

![Diagram: on the left, each bug path gets its own fix and new paths still
reach an uninitialized read. On the right, all paths, including unknown ones,
are caught by one KVGuard check at the KV
read.](/assets/figs/leftover-kv-pages/fig3-point-fixes-vs-invariant.svg)

**Figure 3.** A point fix closes one path at a time and misses the rest;
KVGuard's one check at the KV read stops every path to an uninitialized read,
including unknown ones.

KVGuard checks the rule that must hold whenever KV is touched, not the trigger.
A request reads only entries it wrote, only in blocks it owns, and only within
its own block table row. Systems people know this trade-off from C. You can
patch every buffer overflow one at a time, or you can run AddressSanitizer in
your tests and catch the whole class. KVGuard is the second option for the KV
cache. The same five checks (C1–C5) cover all five bug classes. Without any
per-bug rules, they detect all 29 historical KV cache bugs we collected from
the vLLM and SGLang patch histories, and they found 8 new ones, with no false
positives.

## Cloudflare reached the same conclusion

The most interesting part of Cloudflare's post is about what comes next. After
the four fixes, it says:

> “The per-transfer checksum in #39500 is a first step: it validates the
> handoff from prefill to decode. **Page-level tags go further, because they
> check every read, including reads long after the transfer.**”

Cloudflare built a prototype of these tags. “Every physical KV page carries a
tag that changes when the page is reallocated, each request records the tags it
expects, and the mapping is checked before decode reads the cache.” They also
report its limit:

> “The prototype was also tied to specific attention backends and model
> architectures, so it could not be a general fix.”

Cloudflare is now working with the SGLang team on a production version. This is
the strongest outside support we could ask for. A team that just lived through
the incident concluded that path fixes are not enough. They want a generic
check on every KV read that works across models. That is the problem KVGuard
was designed for.

|               | Page-level tags (Cloudflare prototype, as described)                                                                                | KVGuard                                                                                                                                                                                                                         |
| ------------- | ----------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Tracks        | A page's generation (changes on reallocation)                                                                                       | Per-request permission and per-entry initialization for each block                                                                                                                                                              |
| Checked       | The mapping, before decode reads the cache                                                                                          | Five points from CPU allocation to each KV entry access inside the kernel (C1–C5)                                                                                                                                               |
| This incident | PB1–PB7 were legitimately reserved for the request, so ownership looks valid. An ownership tag alone would not obviously flag them. | The init bits of PB1–PB7 are clear, so C5 fires on the first read                                                                                                                                                               |
| Bug classes   | Stale or reallocated pages                                                                                                          | Double-free, use-after-free, out-of-bounds, uninitialized read, permission violation                                                                                                                                            |
| Status        | Prototype, tied to specific backends and architectures                                                                              | Prototype on vLLM 0.32.0 and SGLang 0.5.22, attached through each engine's plugin mechanism without patching either; covers all 29 historical bugs, found 8 new ones, and reproduces and catches this incident on SGLang 0.5.19 |

The difference in the "this incident" row matters. Here the problem was not a
page that changed owners behind the request's back. The request owned PB1–PB7
and simply never wrote them. To catch that, you have to track which entries
were written, not only who holds the page. We don't know the details of
Cloudflare's production design yet, and we hope it ends up covering both.

## Caveats

- The reproduction above ran on SGLang 0.5.19 with a small model on a single
  GPU, not Cloudflare's GLM-5.3 at production scale. It reproduces the same
  serving bug and transfer shape, not their exact configuration.

- KVGuard is a sanitizer, not an always-on production guard. It adds 3.0%
  (vLLM) and 7.4% (SGLang) geomean time-per-output-token overhead on Qwen 2.5 14B
  and at most 0.11% of the KV cache in memory. The paper's use cases are
  continuous integration, pre-release validation, post-incident debugging, and
  sampled production. Two of them fit this incident: a pre-launch test with a
  prompt longer than the KV pool would have been enough to trigger the check, and
  a sampled fraction of production traffic is where it could have fired during
  the two weeks the leak ran.

## Takeaways

- **A data leak in LLM serving can come from memory management, not from the
  model.** The KV cache is a shared, reused, unzeroed buffer, much like a heap.

- **Point fixes close one path. An invariant closes the class.** Cloudflare's
  shipped fixes are tied to this trigger. Cloudflare itself names a check on
  every read as the next step. KVGuard is that check, built as a general design,
  and it checks "never read KV you did not write" at every KV access, so it
  catches the next leak too, whichever path it takes.

- **Silent bugs need a built-in oracle.** The leak passed every benchmark with
  HTTP 200 and no error frames. Without a check like KVGuard, the oracle is a
  user who happens to recognize someone else's text.

- **Test the edges.** Oversized prompts, aborts, preemption, and disaggregated
  handoffs are where KV block bookkeeping goes wrong. These are also where
  KVGuard found its bugs: it covers all 29 historical KV cache safety bugs we
  collected from vLLM and SGLang and found 8 new ones.

---

Incident details are from Cloudflare's post “[KV cache exposure remediation](https://blog.cloudflare.com/kv-cache-exposure-remediation/)”. Figure 1 is our reconstruction from that description. KVGuard details are from our paper. Draft, not for distribution.
