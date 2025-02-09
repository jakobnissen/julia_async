# Asynchronous programming in Julia

This document is hosted at https://viralinstruction.com/posts/threads/

It is written as a [Pluto notebook](https://plutojl.org). If you can, I recommend running the code in a Pluto notebook so you can play around with it and learn. Alternatively, you can read the HTML file in your browser.

PRs are welcome.

### What this notebook covers:
* Atomic operations
* Atomic memory orderings
* Tasks and how task switching works
* False sharing
* Spinlocks
* Conditions
* Semaphores
* Channels
* `@threads` and `@sync`
