---
title: "The KV Cache Is the New Heap: How Other Users' Prompts Leaked into Cloudflare's GLM Answers"
description: "Cloudflare's GLM-5.3 KV cache exposure explained as an uninitialized KV read, and how KVGuard catches it."
date: 2026-11-05
# author:
#   - "Jonguk Cheong"
published: true
---

In October 2026, Cloudflare
[disclosed](https://blog.cloudflare.com/kv-cache-exposure-remediation/) that
155 responses from the GLM-5.3 model on Workers AI contained pieces of other
users' prompts and outputs. Nothing crashed, nothing was logged, and every
response returned HTTP 200. The leak ran for almost two weeks, until a security
researcher spotted foreign text in their own answers. The model was not at
fault. The serving engine, SGLang, let a request read GPU memory it had never
written.

This is not one engine's bad luck. Nearly every LLM serving stack
keeps its KV cache in a shared GPU buffer that is reused across users and never
zeroed. We found the same class of bug in vLLM and TensorRT-LLM. When that
bookkeeping slips, the result is not a crash. It is a privacy breach that no
status code, log, or benchmark will show. KVGuard, our KV cache sanitizer, is
built for exactly this. It checks every KV read against what the request
actually wrote, so it stops the Cloudflare leak at the first bad read. It also
catches every other path that ends in the same read. This post explains the bug
in plain terms, then shows KVGuard catching it.

## What happened

An LLM stores keys and values (KV) for every prompt token so it can reuse them
while generating. Serving engines keep this KV cache in one large GPU buffer
split into fixed-size **blocks**, and each request has a **block table** that
maps its logical blocks to physical ones. When a request finishes, its blocks
go back to the pool and the next request overwrites them. Blocks are never
zeroed. That is safe only as long as a request reads nothing it did not write.

Cloudflare runs GLM-5.3 with prefill/decode disaggregation: prefill GPUs
process the prompt and ship its KV cache over RDMA to decode GPUs, which
generate the answer. Two things lined up. The advertised context window was
1,048,576 tokens, but the prefill KV pool held only 681,280. And an SGLang bug
let a request that was rejected for being too long keep going as if it were
alive.

![Diagram: prefill GPU rejects an oversized request but sends one KV page;
decode GPU reserved eight pages and attention reads all of them, including
seven stale pages from other
users.](/files/figs/kv-cache-is-the-new-heap/fig1-incident.svg)

**Figure 1.** The Cloudflare incident: a rejected over-length request still
reaches decode, and attention reads seven reserved blocks it never wrote that
still hold other users' KV.

1. Decode reserves eight KV blocks for the request, sized for its full prompt.

2. Prefill rejects the prompt because it does not fit the pool. But the engine
   checked `finished()`, not `rejected()`, so the request still looked alive.

3. Prefill runs a one-token placeholder instead and produces a single KV block.

4. It sends that one block and reports the transfer complete. Decode does not
   check that all eight arrived.

5. Attention reads all eight blocks. Only PB0 was written by this request.
   PB1–PB7 still hold other users' KV, and the answer is built on top of it.

Every one of the 155 affected responses came from a prompt longer than 681,280
tokens.

## Why nothing caught it

Cloudflare's pre-launch tests saw "successful HTTP status codes and a streaming
body with no error frames." Stale KV is well-formed data, so attention computes
over it normally and the model writes a fluent answer. Status codes,
throughput, and error logs all say fine. The only signal was the meaning of the
text, and only the user who received it could tell it was someone else's.

Memory sanitizers do not help either, because they work at the wrong level.
AddressSanitizer never sees GPU memory. NVIDIA Compute Sanitizer sees CUDA
allocations, and the KV cache is one valid buffer allocated at startup: to
`memcheck`, reading PB1 is an in-bounds access, and to `initcheck`, PB1 was
written long ago by an earlier request. Blocks, requests, and block tables, the
level where the bug lives, do not exist for these tools. `memcheck` also slows
serving by 72 to 262 times, far too much for a pre-launch test.

In the KVGuard paper we show that this is not a one-off. Engines manage KV
blocks with their own allocator on top of one GPU buffer, so they inherit the
classic memory-safety bug classes one level up: double-free, use-after-free,
out-of-bounds access, uninitialized read, and permission violation. The
Cloudflare incident is an **uninitialized read**. The same shape appears in
vLLM (bug B6 in our table), where a restore from CPU offload counts two blocks
as loaded and fills only one.

## How KVGuard catches it

KVGuard keeps a small **shadow block** for every physical KV block. It records
two things: which request may touch the block (_permission_), and which entries
have been written in the block's current lifetime (_initialization_).
Allocating a block clears its init bits, a write sets them, and before every KV
read in the attention kernel KVGuard checks that the entry's bit is set (check
C5 in the paper).

![Diagram: KVGuard shadow blocks under each KV block. PB0 is initialized, PB1
to PB7 are not. The C5 check on the attention read fires on
PB1.](/files/figs/kv-cache-is-the-new-heap/fig2-kvguard-check.svg)

**Figure 2.** The same decode step under KVGuard: every block's permission
passes, but only PB0 is marked written, so C5 fires on the first read of PB1.

Permission alone would not catch this incident: PB1–PB7 really were allocated
to the request. The init bits tell a different story. Decode cleared them when
it reserved the blocks, and the transfer wrote exactly one entry, in PB0. The
first time attention touches PB1, C5 fires and names the request, the block,
and the entry.

The transfer is covered too. KVGuard treats it as a read on the sender, whose
source entries must be initialized, and as a write on the receiver, whose
entries become initialized only for what actually arrived. A short delivery and
a full one finish the same way, so the sender passes along the count of entries
it wrote, and the receiver marks only those. That count is the one piece of
metadata KVGuard adds; each node still checks against its own shadow blocks.
Had the sender tried to ship eight blocks it never wrote, C5 would have fired
on the sender instead.

We reproduced the incident on SGLang 0.5.19, the last release before the
upstream fix, with a prefill node and a decode node on one GPU and KVGuard
attached to both. The prefill node rejects the over-length prompt and swaps in
a one-token placeholder. The decode node, which reserved 256 pages while the
transfer delivered one, serves a normal HTTP 200 answer, the incident's
signature. KVGuard reports **4,095 uninitialized reads on that one request**,
each at the exact read where another user's data would enter the answer. A
normal request transfers in full, and KVGuard stays silent.

![Animation: a victim and an attacker share one SGLang service. The attacker's
over-length request is answered with the victim's leftover data (name, recovery
code, PIN, address), while the KVGuard panel reports 4,095 uninitialized KV
reads on that request.](/files/figs/kv-cache-is-the-new-heap/kvguard-demo.gif)

**Figure 3.** The reproduction: a victim and an attacker share one SGLang
service. The attacker's over-length request comes back with the victim's
leftover data, and KVGuard reports 4,095 uninitialized KV reads on that
request. [Watch the MP4](/files/figs/kv-cache-is-the-new-heap/kvguard-demo.mp4) for a
sharper version.

## One check instead of four fixes

Cloudflare's fixes are right, and production systems need them. But each one
closes one trigger:

| Fix                                                           | What it prevents                                                           |
| ------------------------------------------------------------- | -------------------------------------------------------------------------- |
| KV pool resized to about 2× the context length                | Prompts larger than this deployment's pool                                 |
| Retire rejected requests at admission (SGLang #36988, #38935) | A rejected request reaching decode                                         |
| Deferred KV release by default (#37454, #41023)               | KV freed while a transfer is still in flight                               |
| KV checksum on the prefill-to-decode handoff (#39500)         | Corrupted data in the transfer                                             |
| **KVGuard check C5**                                          | **Any read of a KV entry its request has not written, from any code path** |

The same leak could return by another route: a preempted request that resumes
with part of its KV missing, a prefix-cache bookkeeping slip, or a kernel that
rounds a partial block up. This is not hypothetical. Of the 29 historical KV
cache bugs in our paper, eight are uninitialized reads, seven of them in
SGLang. Each arrived by its own path and was fixed by its own patch after
someone noticed wrong output.

![Diagram: on the left, each bug path gets its own fix and new paths still
reach an uninitialized read. On the right, all paths, including unknown ones,
are caught by one KVGuard check at the KV
read.](/files/figs/kv-cache-is-the-new-heap/fig3-point-fixes-vs-invariant.svg)

**Figure 4.** A point fix closes one path at a time and misses the rest;
KVGuard's one check at the KV read stops every path to an uninitialized read,
including unknown ones.

KVGuard checks the rule, not the trigger: a request reads only entries it
wrote, in blocks it owns, through its own block table row. This is the
AddressSanitizer trade-off applied to the KV cache. You can patch buffer
overflows one at a time, or you can run a sanitizer in your tests and catch the
whole class. KVGuard's five checks (C1–C5) cover all five bug classes. They
detect all 29 historical bugs from the vLLM and SGLang patch histories and
found 8 new ones, with no false positives.

## Cloudflare reached the same conclusion

After listing its fixes, Cloudflare's post calls the transfer checksum "a first
step" and says that "Page-level tags go further, because they check every read,
including reads long after the transfer." Cloudflare built a prototype in which
every physical page carries a tag that changes on reallocation, but reports
that it was "tied to specific attention backends and model architectures, so
it could not be a general fix." Cloudflare is now working with the SGLang team
on a production version.

A team that just lived through the incident concluded that path fixes are not
enough, and that the answer is a generic check on every KV read. That is what
KVGuard is. One detail matters for this incident, though. A tag that changes on
reallocation tracks who owns a page. Here, PB1–PB7 were legitimately reserved
for the request, so ownership looked valid; what was missing was the write.
Catching that takes per-entry initialization, not only ownership, and we hope
the production design covers both.

## Notes

- The reproduction used a small model on a single GPU, not GLM-5.3 at
  Cloudflare's scale. It reproduces the serving bug and the transfer shape, not
  their exact configuration.

- KVGuard is a sanitizer, not an always-on production guard. It adds 3.0%
  (vLLM) and 7.4% (SGLang) time-per-output-token overhead on Qwen 2.5 14B and
  at most 0.11% of the KV cache in memory. It is meant for CI, pre-release
  validation, post-incident debugging, and sampled production traffic. Here, a
  pre-launch test with one prompt longer than the KV pool would have triggered
  it.

## Takeaways

- **A leak in LLM serving can come from memory management, not the model.** The
  KV cache is a shared, reused, never-zeroed buffer, much like a heap.

- **Point fixes close one path. An invariant closes the class.** "Never read KV
  you did not write," checked at every KV access, catches the next leak
  whichever path it takes.

- **Silent bugs need a built-in oracle.** This one passed every benchmark with
  HTTP 200. Without a check like KVGuard, the oracle is a user who recognizes
  someone else's text.

For more details, read our paper: [KVGuard: A KV Cache Safety Checker
for LLM Serving Systems](https://arxiv.org/abs/2611.06138).

Source code is available at GitHub: [compsec-snu/kvguard](https://github.com/compsec-snu/kvguard/).

---

Incident details are from Cloudflare's post: [KV cache exposure
remediation](https://blog.cloudflare.com/kv-cache-exposure-remediation/).
Figure 1 is our reconstruction from that description.
