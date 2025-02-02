### A Pluto.jl notebook ###
# v0.20.4

using Markdown
using InteractiveUtils

# ╔═╡ 21b2cbda-17d6-4466-adbc-5e513482e1af
begin
    using PlutoUI
end

# ╔═╡ 8f6cf27f-5648-40ab-b029-d52c0eaf3883
using .Threads

# ╔═╡ 8b83e436-dc12-11ef-1b27-1d3fdefb24c1
md"""
# Asyncronous programming in Julia
_Written 2025-12-26_

**Find this notebook at https://github.com/jakobnissen/julia_async**

When I read blogs or textbooks on programming, I'm struck by the variety of use cases and contexts programming is used in, and how that diversity shapes how people think about the craft.
Many of the blogs I read describe their programming as revolving around websites and networks, where themes like communication protocols and JavaScript frameworks play major roles.
In my eight years of scientific programming, I've never had to think about any of that stuff. To me, all of that is like a parallel universe of software which interacts very little with what I do on my job, writing scientific software.

Most of the blogs I read mention asyncronous programming in this context of 'network coding', and so I thought that async was mostly about how your program handled waiting for network data.
An important subject, perhaps, but surely something I could ignore as a scientist.

Oh boy was that wrong.

In this notebook, I'll dig into asyncronous programming in Julia.
It will be about the overall design of async in the language,
a little about how it works under the hood,
and the basics of how to get started with using it.
"""

# ╔═╡ b278c476-74e9-4399-a05c-7c15111bfd3c
TableOfContents()

# ╔═╡ 17ddbb08-cd8d-446e-b806-dc3000dc2184
md"""
## Why is async important?
The defining property of asyncronous programming is having different parts of your program running at the same time.
To do this, the programming language needs to somehow abstract over 'units of computation' as separate 'tasks' that can be started, paused, restarted and stopped.

In Julia, this is fittingly modelled with the `Task` type.
Tasks are most easily created with the `Threads.@spawn` macro, which will wrap as Julia expression in a zero-argument function, and then run that function as a task:
"""

# ╔═╡ 2bd97906-edc8-48e8-ac2d-6a87a2e01fe5
task = @spawn begin
	x = 1 + 1
	return x + 1
end

# ╔═╡ af3b6b92-d1a1-43de-a88b-605f559e1d68
task

# ╔═╡ c4f33908-efab-4654-b9dd-b4e46573428a
md"""
Tasks are first _created_, then _started_, after which they can be _paused_ and _resumed_ an arbitrary amount of times during their lifetime.
When the function they wrap returns, the task is _done_.
If the function in the task throws an unhandled exception, the task has _failed_.
Finished and done tasks cannot be restarted.

To obtain the return value of a task, use `fetch`. 
"""

# ╔═╡ 5e45c378-3788-484c-906b-86586c8cd7c8
fetch(task)

# ╔═╡ a8acd763-7068-4a2c-9dd9-8f926680f8b7
md"""
The most common (but not _only_!) use case for tasks is to allow _parallel computation_, where multiple tasks may run on your computer at the same time.

When tasks are started, they run on an underlying _thread_ provided by the operating system.
The total number of threads currently needs to be set from command line when starting Julia using the command-line flag `-t`.
It's the job of the operating system to provide hardware resouces (e.g. CPU time)
for each of the threads.
A CPU core can only run one thread at a time, so the number of threads are usually a small, fixed number corresponding to the core count of the CPU.
Laptop CPUs today typically have 8 or more cores, so parallel computation unlocks serious performance compared to using a single thread. 

You can check the number of current threads with the function `Threads.nthreads()`:
"""

# ╔═╡ de1f77c2-bdbb-4192-ba24-da41489c0a8b
Threads.nthreads()

# ╔═╡ f74b1284-dece-4216-bb06-29514415ff5f
md"""
By starting Julia with more than one thread, multiple tasks can run concurrently.
Julia intentionally provide few abstractions for the threads themselves, because they are supposed to be abstracted away.
As a programmer, your focus is supposed to be on managing your own Julia code in the form of `Task`, and you can usually simply rely on Julia to do a reasonable job of scheduling all tasks across the available threads in an efficient manner.

Precisely because the user is not supposed to think about threads, Julia has great freedom in how it maps tasks to threads:
Your task may be run on any available thread, even moved between different threads while running, and started and stopped at any point (_mostly_ any point, I'll get back to that later).
"""

# ╔═╡ ef36118e-2fdf-4c99-a9da-f8cbc6885fb3
md"""
One of the most basic design patterns for using parallelism is to spawn and fetch tasks within a single function. For example, in the following case: 
"""

# ╔═╡ 67664ef0-0f00-4388-a47c-9d97d7b443a5
begin
	simple_function_1(x::Int) = div(x, 2) + 1
	simple_function_2(x::Int) = sqrt(x) + 9

	function complex_function(x)
		t = @spawn simple_function_1(x)
		a = simple_function_2(x)
		return (fetch(t)::Int, a)
	end

	complex_function(9)
end

# ╔═╡ 0f800d3f-34ae-4f6c-b6bc-d7c82c1c1af2
md"""
In `complex_function`, the calls to the two 'simple functions' do not depend on each other, and may be run in any order. Hence, we can run one of them as a separate task, which then runs in the background while the other simple function is executed.

At the time of writing, Julia unfortunately cannot do type inference on `fetch` which always infers to `Any`.
Hopefully, that will be fixed in the near future.
Until then, you might need to annotate the return value of `fetch` with the expected return type to obtain type stability.

In round numbers, spawning and fetching a task has a rather large overhead of five microseconds and 16 KiB RAM.
For this reason, the above pattern is really only useful in relatively high-level function calls.
"""

# ╔═╡ 20ee5cfa-b80c-4a2f-8314-67048c1c429b
md"""
## The law of async
Since async is all about splitting your program into stoppable and resumable chunks part of your program, making your code asyncronous can be invasive, in that it can have a large impact on the structure of your entire program.
Async is also (deservedly) infamous for being tricky and prone to bugs.

To reduce the risk of bugs, it helps to internalize the cental law of async:

> Mutation requires exclusivity

That is, if one task mutates some data, no other task must access that data (read from or write to it) at the same time.
The reason is that most code relies on the assumption that data doesn't spontaneously change while it's being operated on.
If task A mutates some data while task B operates on it, from the point of view of task B, the data _does_ appear to spontaneously mutate.

In this spirit of legalism, let's write some sections to this law:

§ 1a. The different elements of an `Array` are considered different data.
  That is, it's allowed for two tasks to mutate or operate on
  different elements of the same array.

§ 1b. Some operations appear to only affect one element of the array, but
  actually affects all of them. E.g. `push!` might cause the whole array
  to be resized, which requires copying the memory of the whole array.
  Therefore, such an operation counts as mutating _every_ element.
  Similarly, in Julia, the elements of `BitArray` are not independent:
  Because multiple bits are stored in the same integer in an underlying `Array`        in the bitarray,
  mutating one element of the array actually mutates the whole integer,
  which affects multiple elements in the `BitArray`

§ 1c. If no task is mutating a piece of data, then it may be shared freely
      with no worries. For example, multiple tasks may look up in the same
      dict, or copy the same string, concurrently.
"""

# ╔═╡ a279c000-2154-44b9-bb72-41862b61fcbc
md"""
## Data races

Let's have a look at an example of what happens when you violate the law of async.

In the code below, `add_ten_million!` will add ten million to a reference holding an integer, one at a time. The function `increment_occasionally` will check the reference, add its content to a result, and then zero the reference.
You can envision this as modelling a 'producer' task and a 'consumer' task.

The code contains a function call to `Threads.atomic_fence`.
You can ignore this for now - I'll get back to it later.
"""

# ╔═╡ 0668560d-d2ff-49ae-a5ae-3a92ba269e53
function add_ten_million!(ref)
	for i in 1:10_000_000
		ref[] += 1
		# I'll explain what this fence does later
		Threads.atomic_fence()
	end
end;

# ╔═╡ a40cd157-fde1-49be-9156-0b8caa12e5a5
function increment_occasionally(ref)
	t = time_ns()
	result = 0
	while time_ns() - t < 1_000_000_000
		result += ref[]
		ref[] = 0
		Threads.atomic_fence()
	end
	result
end;

# ╔═╡ fc99d8b6-9b32-46a4-bde0-9108b029e43e
md"""
Below, I run the two functions in parallel, where they work on the same ref.
Clearly, when they are done, the result will be ten million... right?
"""

# ╔═╡ 602c3a65-79c2-4e6b-a70d-c9b3c1df20ca
let
	ref = Ref(0)
	t = @spawn increment_occasionally(ref)
	add_ten_million!(ref)
	# Fetch the result and add anything left in `ref`
	# not yet taken by `increment_occasionally`
	fetch(t) + ref[]
end

# ╔═╡ 592fc034-8344-4cb7-b378-6ced7205ad9e
md"""
The result is _undeterministic_ - every time you run it, it's likely to give a different number.

The reason it doesn't behave as expected is that both tasks mutate `ref` concurrently, violating the law of async.
We call such situation _data races_.

In this particular example, the problem occurs because of the details of how the line `ref[] += 1` is implemented.
In Julia, `ref[] += 1` is equivalent to `ref[] = ref[] + 1` - actually three operations in disguise, it's actually three operations:

1. Load `ref[]`
2. Add 1 to the loaded value
3. Store the result back into `ref[]`.

Suppose now `ref` has a value of 5, and task A runs `add_ten_million` thus incrementing `ref`, and task B runs `increment_occassionally` and thus zeros `ref`.
There is is some chance that it could be executed in the following order:

1. Task A loads `ref[]` getting 5
2. Task B computes `result += ref[]`
3. Task A adds one to the loaded value of 5
4. Task B zeros `ref`
5. Task A sets `ref` to 6

If that occurs, `ref` is not zeroed like it's supposed to, and therefore the 5 previous increments will be added twice to `result`.

Here, the underlying cause is that `ref[] += 1` is composed of several steps, and that the other task is able to read or modify a value that is in middle of these steps.

In computer science terms, we say that the problem is that `ref[] += 1` is _not atomic_. Here, "atomic" is used in the original Greek sense, meaning _indivisible_.
An atomic operation is one that can never be observed is a state of partial completion - it either has not happened yet, or is already complete.

### Even single CPU instructions are not atomic
It is tempting to try to solve data races like the one above by simply choosing operations which are not implemented in terms of multiple operations.
If you look into the generated code for the `add_ten_million!` function above, you will see that the line `ref[] += 1` is compiled to a single instruction - at least on my computer with a x86-64 CPU.
So naively, one would think that this single instruction would be atomic - not composed of multiple, smaller steps. Nonetheless, the data race happened. Why?

In the CPU, single CPU instructions may be executed in terms of smaller micro-operations, the details of which is an implementation detail of the CPU. Further, the CPU's memory system is complex and multi-layered, and there is no guarantee that when a computer stores a value to memory, other parts of the CPU will immediately be able to see the stored value.
Finally, on the programming language level, while Julia might implement the increment as a single instruction right now, Julia provides no guarantee that the compiler will generate the same code in the future.

This will be a recurring theme in this notebook: The rules of async are abstractions that can't easily be explained in terms of the underlying implementation, because the implementation is complex and opaque.
As a programmer, your best bet is to adhere to the abstraction and not try to outsmart it by peeking under the hood. 

Once we know that
1. All CPU operations may be split into multiple steps in the CPU and the memory hierarchy, and
2. Interacting with data that is in a partially processed state may cause a data race,

we find ourselves forced to conclude that two different tasks can never interact with the same data at all, and so the prospect of writing ayncronous code appear completely hopeless.

Fortunately, Julia provides dedicated _atomic operations_ to address this problem. The language guarantees that these operations are always compiled down to dedicated atomic CPU instructions, which the CPU in turn guarantees the atomicity of.

Let's try to solve the bug using atomic operations.
To use atomic operations in Julia, we need to use a mutable struct, with the relevant field marked `@atomic`:
"""

# ╔═╡ a5fa1503-5880-4d0e-aba8-0c3ee34b6dfa
mutable struct AtomicInt
	@atomic x::Int
end

# ╔═╡ 422c8758-e0f6-491e-ad0d-743f4d9e7c48
md"""
We can now rewrite the functions above, using this atomic integer instead of a normal `Ref`.
Note that all operations on atomic fields needs to be marked `@atomic`.
"""

# ╔═╡ 107291d1-1c00-45a7-9225-be541ff44ab6
function add_ten_million_atomic!(atomic)
	for i in 1:10_000_000
		@atomic atomic.x += 1
	end
end;

# ╔═╡ 4266d974-0dca-4798-9952-2a7e8c77968c
function increment_occasionally_atomic(atomic)
	t = time_ns()
	result = 0
	while time_ns() - t < 1_000_000_000
		# Atomic swap does a load and a store in a single atomic
		# operation, here it swaps the atomic.x field with 0.
		result += (@atomicswap atomic.x = 0)
	end
	result
end;

# ╔═╡ 6a1c5924-92b6-40ef-967f-494332ade500
let
	atomic = AtomicInt(0)
	t = @spawn increment_occasionally_atomic(atomic)
	add_ten_million_atomic!(atomic)
	fetch(t) + @atomic atomic.x
end

# ╔═╡ 718eac91-b4d1-4dee-ac67-76e4cb8ef341
md"""
Voila! The bug disappeared.

## Memory re-ording
Atomic operations have a _memory ordering_ associated with them.
To understand memory ordering, it is necessary to take a detour into how Julia's compiler is able to re-order memory operations in general.

### Re-ordering in single threaded code
If we consider a simple Julia function like the one below:
"""

# ╔═╡ fde5713b-2774-43dc-90d1-36b1446d4540
function order1()
	b = 1 + 1
	a = 1
	a = 2
	return a + b
end;

# ╔═╡ 19609694-3c8e-4b46-be18-63011e315308
md"""
As we know and love, the Julia compiler will change the code being optimised, in order to make it run faster.
For example, it may move the computation of `b = 1 + 1` down onto the last line, such that it becomes `return a + 2`.
In general, the compiler is free to move computations around, such that they are run in a different order from what they were defined in.


Similarly, it may delete the `a = 1` like, since `a` will be overwritten immediately after, anyway.
But wait: If the compiler is able to move computation around, why can't it reorder `a = 2` to come before `a = 1`, and then delete the `a = 2` line instead?

The obvious answer is that the compiler must have a notion of _dependency_: Computing `b` has no dependency on the computation of `a`, and so may be moved around freely with respect to `a`. 
In contast, dependent operations must have a notion of _happens before_, i.e. `a = 1` happens before `a = 2`, so these two lines can't just be rearranged.

The compiler's concept of happens-before relies on the concept of a data dependency.
Some data (i.e. a variable or a memory location) `A` depends on data `B` if `B` is being used to mutate `A`.

Once again, I want to stress that _happens before_ is an __abstraction__.
In practise, `order1` will compile down to simply `return 4`, and when the program runs, there won't exist any data that corresponds to the variables `a` or `b`.
Nonetheless, we can still unambiguously say that `a = 1` happens before `a = 2`.

As we've seen before, if memory is being mutated, it can _only_ be shared between tasks if the mutation is atomic, since sharing non-atomically mutated memory may cause a data race.
For this reason, barring atomic operations, data in different tasks cannot have a valid data dependency of each other, and as a consequence, only atomic operations can establish a happens-before relationship between two tasks.

### Happens-before relationships between tasks
Let's look at the happens-before relationships in the code below and consider what that implies for the result
"""

# ╔═╡ 9fe22bc2-2c4a-423d-85cb-60a16ad68ea3
function overwrite(a::Ref{Bool}, b::Ref{Bool})
	a[] = true
	b[] = a[]
end;

# ╔═╡ 00e9e859-3238-41f8-93ca-b2243495083b
function observe_overwrite()
	a = Ref(false)
	b = Ref(false)
	t = @spawn overwrite(a, b)
	b[] ? a[] : true
end;

# ╔═╡ b74ae921-f376-4a40-b042-4e7a777902ef
md"""
Here, `observe_overwrite()` may return both `false` and `true`.

This may be surprising. After all, `b[]` is guaranteed to happen after `a[]`, since `b` depends on `a`.
Therefore, in `observe_overwrite`, if `b[]`, then `a[] = true` must have already happened, and therefore, `a[]` necessarily must return `true`.

Right?

Not so. What we missed with the above analysis is that, absent atomic operations, there is no notion of happens-before between tasks. So, the function `observe_overwrite` could observe the operations in `overwrite` in any order.
Remarkably, this includes the order where `b` stores `true` __before__ `a` does, despite `b` supposedly loading its value from `a`!
Therefore, `observe_overwrite` could plausibly load `true` from `b[]`, and then return a `false` from `a[]`!

We can construct even more cursed situations where the lack of happens-before between tasks mean that one task will implicitly observe another task doing its operation in an absurd and seemingly impossible order.
However, the conclusion will be the same: Use atomics when sharing data between tasks, or else you'll get bugs.

### Atomic memory orderings
It's important to keep in mind _why_ our compiler, CPU and memory re-order operations and make all this so hard to reason about: Speed.
Computers could be built perfectly syncronously with no out-of-order execution, but they would run tens, or hundreds of times slower.
The more we restrict out-of-order computation using atomics, the slower our program runs.
Ideally, we want to place only the exact amount of re-ordering restrictions to allow our async code to be correct, but no more.

Therefore, atomic operations come with a selection of _memory orderings_, such that we can pick the most lax ordering that still makes our program work.

#### Ordering: Sequentially consistent
The default memory ordering, used if not explicitly specified, is also the strongest one: _sequentially consistent ordering_.
When one task observes the result of a sequentially consistent operation, it is guaranteed to be able to observe all previous reads and writes of that task, and to not yet be able to see all future reads and writes.
In this way, it acts like a memory barrier: No operations can be re-ordered across the barrier, either in the before => after direction, nor in the after => before direction, no matter what thread you are observing from.

We can fix the above example with a sequentially consistent operation:
If the observer task atomically reads `b.x` as `true`, the atomic operation `b.x = a[]` is fully completed, in which case `a[] = true` is guaranteed to have been completed due to the memory ordering guarantee of sequentially consistent.
"""

# ╔═╡ fd87476d-b32b-4785-9fdc-21da66b9adaa
md"""
#### Ordering: Monotonic (or relaxed)
At the opposite end from sequentially consistent ordering, we have the _monotonic_ ordering, also called _relaxed_ ordering in other languages.
This ordering provide _no restrictions_ on memory re-ordering, allowing the computer full freedom to re-order operations around for maximal performance.

Consider the example in `add_ten_million_atomic!`.
Here, we don't really care if the compiler moves around the atomic loads or stores, e.g. by unrolling the loop, or even by the compiler moving the atomic increments outside the loop, and switching the ten million atomic increments to a single atomic addition by ten million.

For this reason, that example would have been best solved by using monotonic operations.
"""

# ╔═╡ 27133bd1-433e-4bc4-ac6e-c06b9c245b6e
md"""
#### Ordering: Acquire and release
It turns out, that, most of the time when we _do_ care about memory ordering, we don't require the kind of complete memory barrier that the sequentially consistent ordering provide.

One of the most common scenarios in async programming is when one task computes value, then atomically modifies some flag to signal the value is ready.
Meanwhile, another task reads the flag, waiting for it to be changed before the task loads the value and continues processing it.

An example could look like this:
"""

# ╔═╡ 58b98795-03ad-44e7-ab68-cc5e4e397108
mutable struct AtomicBool
	@atomic x::Bool
end

# ╔═╡ 65fc3a2d-de89-4cc2-8f1e-dbc2f90c416d
function overwrite_atomic(a::Ref{Bool}, b::AtomicBool)
	a[] = true
	# Sequentially consistent ordering is default,
	# so we could have omitted it here.
	@atomic :sequentially_consistent b.x = a[]
end;

# ╔═╡ a08bd0d6-776e-46a7-a186-614cc0bbd65d
function observe_overwrite_atomic()
	a = Ref(false)
	b = AtomicBool(false)
	t = @spawn overwrite(a, b)
	(@atomic :sequentially_consistent b.x) ? a[] : true
end;

# ╔═╡ e07e174d-3719-4025-91aa-f56365a68453
function mark_when_ready(is_ready, shared)
	sleep(0.2) # do some computation
	shared[] = 42
	@atomic :release is_ready.x = true
end;

# ╔═╡ d11037b5-241d-4878-9602-0043bb21e72b
function return_when_ready(is_ready, shared)
	while !(@atomic :acquire is_ready.x)
		# Only check once ever 10 miliseconds
		sleep(0.01)
	end
	shared[]
end;

# ╔═╡ 96d968b3-4662-4985-9a81-7fe6cdcbb524
let
	is_ready = AtomicBool(false)
	shared = Ref(0)
	t = @spawn return_when_ready(is_ready, shared)
	sleep(0.1)
	mark_when_ready(is_ready, shared)
	wait(t)
	shared[]
end

# ╔═╡ 2a383feb-22d8-48d8-b247-c20ec5bbe91b
md"""
Here, in `mark_when_ready`, it's crucial that no operations are moved from in the before => after direction across the atomic modification of `is_ready`.
For example, if `shared[] = 42` was moved to after the atomic operation, then the other task might use `shared` before it was ready.

But the opposite isn't true! It would be no problem if the compiler moved some non-atomic operations in the after => before direction across the atomic operation.

In `return_when_ready`, it's the opposite situation: `shared[]` cannot move in the after => before direction, but it would not be a problem if there was some operation above the atomic load that was moved to after.

Ad demonstrated in the example, this is what the _acquire_ and _release_ orderings are used for: The release ordering is used for a write operation to release some data to another task, and the acquire ordering is used for a read operation to access data modified in another task.

#### Ordering: Acquire-release
There exists certain atomic operation which do both a read and a write at once. For example, the function `Threads.atomic_cas!` is equivalent to this function

```julia
function cas!(x::Threads.Atomic, cmp, newval)
    old = x.x    
	if x.x == cmp
		x.x = newval
	end
	old
end
```

, but done in one single atomic operation.  Here, the read part of the function has acquire memory ordering, and the write part had release ordering.

I still don't understand the difference between acquire-release and sequentially consistent ordering.

### Atomics are mostly used to implement other async abstractions
The abstraction of atomic operations are the lowest level async abstraction provided by the CPU itself, and, through the compiler, the programming language.

Not only are they extremely low level in that they are essentially async-friendly single CPU operations, their memory ordering and the happens-before relationship is also difficult to reason about.

Direct use of atomics can also be extremely _inefficient_.
For example, the `return_when_ready` function implemented above will continuously check whether the shared value is ready, consuming CPU cycles in the process.
It would be much better if the function instead could be paused and only resumed once the value was ready.

In practice, most use cases of async don't directly use atomics, but will instead control tasks through  more user-friendly higher level abstractions implemented in terms of atomic operations.

Before we turn to those abstractions, let's look at what makes up a task itself.
"""

# ╔═╡ 1d70bc25-b941-4481-8579-80b70e7b6846
md"""
## Tasks and task switching
In order to be suspended and resumed, a task needs to keep track of its current
progress. The progress of a task, or its state, is defined to two things:

First, the current state of the CPU registers. If the compiler statically knows
all the points in the code where a task can be suspended,
the compiler may make sure only a small subset of the registers
are in use at that time, such that the task needs to store less state.
As we will see, in Julia, tasks voluntarily gives away control to another task, and so the compiler
is able to do this optimisation.

Second, a task needs a _stack_. This is the same kind of basic stack used by all
programs, which we know and love from e.g. stack overflow errors.
The stack is analogous to a `Vector{UInt8}` - a region of memory
with a pointer that keeps track of how much of the region is in use at any given time.
The two main operations the stack can do is _pushing_ (analogous to `push!`), which
adds an element to the end of the stack, and popping (i.e. `pop!`),
which removes the last pushed element.
All information about the program progress that cannot be kept in the registers is
stored on the stack.

When the register state is saved on task suspension, the
registers are typically pushed onto the stack; conversely, they are popped from
the stack into the registers upon resuming the task.
This ensures that the stack contains all the information needed to resume a paused
task.

In Julia, tasks carry their own independent stack. This fact causes stacks to cost
some time and memory (16 KiB-ish) to instantiate.
"""

# ╔═╡ 6b900c42-127e-463f-b941-c321297537f3
md"""
### How does task switching work?
Conceptually and implementation wise, there are several similarities between
a _function call_ and a _task switch_.
At a function call, the CPU will pause the execution of the current function and
give control to a different piece of code, which is then automatically returned to
when the function returns. The similarities to task switching are obvious.

So: How do function calls work?

In x86-64 CPUs, the rip (register instruction pointer) register stores
the memory location of the next instruction to be executed by the CPU.
To begin executing a function, we need to change the value of this register to
point to the first instructions of our callee.
Changing the value of the rip register is done with a _jump_ instruction -
i.e. we say that the program jumps to some memory location.
However, first, the CPU needs to make sure it can resume the work when the callee
returns.

By convension, on Linux on x86-64 computers, the seven registers rsp, rbx, rbp,
and r12-r15 are so-called _callee saved_. This means that no function is allowed
to change these registers when being called: Either they must leave the registers
alone, or else they must make sure to push the original state of the registers to
the stack, and pop them from the stack back into the registers, in order to restore
them, before returning.

Therefore, any _caller_ can assume no callee changes these registers, and can store
information in them. Any state that can't be kept in these registers are pushed
to the stack.
Aside from the callee saved registers, the CPU only needs to store the aforementioned rip
register on the stack, in order to restore the CPU state.

So, to call a function, the CPU needs to:
1. Store all local state in either the seven callee-saved registers or on the stack,
2. Push the rip register to the stack
3. Move the memory location of the callee into the rip register

The `call` assembly instruction will do the last two points.

When the callee has been executed, and control needs to return to the caller,
this is what needs to happen:

1. Clean up the stack by popping any data off it, such that it's in the same state
   the callee found it in
2. Pop the stack into the rip register. Since the last element on the stack placed
   by the caller was the rip register, doing this returns execution to the instruction
   immediately after `call` in the caller.

The `ret` instruction will pop the last element of the stack into the rip register.

Task switching then, is quite similar to function calling: When a task gives control,
it pushes its callee-saved registers and the rip register to the stack.
To resume control of a task, all it needs is a pointer to its stack, from which
it will pop offs its register state and then resume execution by popping off the
rip register with a `ret` instruction.
"""

# ╔═╡ 725773df-24c7-4547-84fc-3cd163d19136
md"""
### Tasks usually switch to the scheduler
In Julia, tasks can switch to other tasks with the low-level `yieldto` function.
This is not usually practical: This would require every task - i.e. every piece
of user code - to be aware of which other tasks are awaiting to be switched to,
and also to know when to switch to them. How could a library developer possibly
know what other code is running in a given session that should be switched to?

Instead, a program called the scheduler keeps track of all tasks in the process.
The scheduler is a C program part of the Julia runtime, similar to the garbage
collecter.
Having a single centralized program to control task switches makes things much
easier for the programmer: Every task simply switches to the scheduler, which
controls which task to switch to next.
If the Julia process has multiple threads, the scheduler may run multiple tasks
simultaneously.

User code may switch to the scheduler explicitly with the `yield` function.
More commonly, any _blocking operation_ automatically switch to the scheduler.
A blocking operation is an operation that needs to wait for something.
We've already seen some blocking operations: The channel operations `put!` and
`take!` block if they aren't able to push or pop elements immediately.
So do fetching a task (if the task hasn't finished), and locking a lock (if it's
already locked).
In Julia, I/O operations that interact with resources provided by the operating
system, like stdout, stderr, or files, also yield control to the Julia scheduler,
since they require waiting for the operating system to provide the resource.

The rationale of blocking operations is that, if a task needs to wait for e.g.
the filesystem or a lock, then the scheduler might as well switch to another task
that is maybe able to do work.
"""

# ╔═╡ 5688d79a-0593-4722-b4f6-252b327746b2
md"""
### Tasks and the garbage collector
When the garbage collector (GC) runs, it mutates the data structure that keeps track
of heap allocations.
As the golden rule of async goes, _Mutation requires exclusivity_.
That means no other task can allocate memory at the same time as the garbage collector runs.
Practically speaking, this means that when one tasks triggers the GC, the GC can't run
until all other tasks has been blocked  - we say that Julia's GC is a stop-the-world GC.
In turn, that means that all running tasks need to know that the GC wants to run,
such that they can yield.
How is this coordinated?

When the GC wants to run, it modifies a pointer in the thread-local state to
an invalid memory location.
The function `GC.safepoint()` loads data from this pointer. If the pointer is
invalid, this triggers a SIGSEGV (segfault signal), which is handled by Julia's custom SIGSEGV handler,
to block the current thread.
If the pointer is valid (i.e. the GC has not signalled it wants to run), this pointer load has no effect and takes only half a nanosecond.
Therefore, calls to the `GC.safepoint()` is peppered across various functions in the Julia runtime, like memory allocation or IO.

The inter-thread coordination needed to run the GC impacts how the user needs to write multithreaded code:

First, allocation-heavy code should be expected to scale worse with the number of threads than non-allocating tasks,
because each thread creates garbage, so the GC needs to run more often, pausing every other thread.

Second, users need to be wary not to write code where _one_ task allocates memory, triggering the GC, when _another_ is running code that does not call `GC.safepoint()`, by allocating, doing IO, yielding to the schedular or doing dynamic dispatch.
If this happens, the first task will trigger the GC, blocking all tasks with safepoints, while the safepoint-less task will continue to run. In the worst case, this can lead to deadlocks.
This issue occur most commonly when one task calls external code, such as a C library.
"""

# ╔═╡ a0ed20e1-da3f-4dbc-83b1-1399f0dea805
md"""
## High level interface
I won't go through all the various different async-related APIs here,
but just a selection of the ones I find the most useful.

#### Tasks
A `Task` is most easily created and started with the `Threads.@spawn` macro:

@@juliacode
```
julia> using .Threads

julia> task = @spawn begin
       x = 1 + 1
       sleep(5)
       x + 1
       end
Task (runnable, started) @0x0000788908e3fd00
```
@@

Julia is now free to run the task whenever it wants to, on whatever thread it wants
to, and will do so at the first given opportunity.
The `@spawn` macro returns instantly while the task is running in the background.

When you call `fetch` on the task, Julia will wait for the task to finish, and
return the result of the task - or throw a `TaskFailedException` if the computation
in the task threw an error:

@@juliacode
```
julia> fetch(task)
3
```
@@

Julia currently doesn't do any type inference across tasks, so the result of `fetch`
is always inferred to just `Any` - hopefully, this will change in the future. 

Spawning, running and fetching a task has some overhead. On my laptop, it takes
between one and five microseconds, depending on the circumstance, and consumes
about 16 KiB RAM.

#### `@sync`
If you spawn tens of tasks, it can be cumbersome to store them all and properly
call `fetch` on them.
The `@sync` macro can be applied to a block of code. This block of code will then
not complete until all tasks spawned in that block has finished:

@@juliacode
```
julia> @sync begin
           @spawn some_work()
           @spawn other_work()
       end
       # Here, both task spawned are guaranteed to have finished
```
@@

Note that `@sync` only works on tasks spawned directly in the expression on which
`@sync` operates. If `@sync` is applied to e.g. a function which spawns a task,
`@sync` will not know about this task.

#### `@threads`
The `@threads` macro is a convenience method that spawns a number of tasks
and then share the iterations of a for-loop between the tasks.
When the 'threaded' for-loop ends, all the tasks are guaranteed to have finished.
It really should have been named `@tasks`.

The precise meaning of how many tasks it spawns and how it splits the iterations
between them can be configued.
The default will call `firstindex` and `lastindex` on the thing you're looping
over in order to compute how to split the iterations between the tasks.
The precise manner of the default is subject to change:

@@juliacode
```
julia> @threads for i in 1:10
           println("Doing iteration $i")
       end
Doing iteration 6
Doing iteration 5
Doing iteration 3
Doing iteration 7
Doing iteration 8
Doing iteration 4
Doing iteration 1
Doing iteration 10
Doing iteration 2
Doing iteration 9
```
@@

`@threads` have quite high level 'don't think about it' API. One one hand, this
makes it simple to use. On the other, it means you can assume very little about
how the individual iterations are run.
For this reason, you should always assume the iterations can run in any arbitrary
order, including simultaneously (or in reverse order, for that matter).

#### Locks
The `ReentrantLock` data type is the only type of lock in Base Julia that is suitable
for general use.
Locks are only good for one thing: Ensuring that only one task accesses a piece
of data at a given time.

A task can `lock` a lock, and a locked lock can then be `unlock`ed again by the same task.
A lock can only be locked by one task at a time. If task A attempts to lock a lock
locked by task B, task A will wait patiently for task B to unlock it first.

Conveniently, the `@lock l expr` macro expands to:

@@juliacode
```
lock(l)
try
    expr
finally
    unlock(l)
end
```
@@

Which makes sure the lock is unlocked by the task running the macro, even if the
expression errors.

#### Channels
A `Channel` can be thought of as a collection, similar to a `Vector`, which has
all its operations guarded by locks.
This means you can freely operate on a channel with any number of threads at a time,
since the locks stored inside the channel will make sure that the golden rule of
async is never broken.
A `Channel` has a size - that's maximum number of elements it can contain. 

* `put!(::Channel, ::Any)` puts an element into the channel if there is room.
  If not, it will wait until there is room.
* `take!(::Channel)` removes and returns the first element in the channel,
  similar to `popfirst!`. If there are no elements, it will wait until an
  element appears.
  If a channel has size zero, and one task waits for a `put!` call and another
  waits or a `take!` call, then the two `put!` and `take!` calls will both succeed.
* `close(::Channel)` closes the channel. This causes any `put!` calls to throw
  an error, and any `take!` on an empty, closed channel will also throw.

Channels can be iterated over. This will repeatedly call `take!`, once for each
iteration. If a channel is iterated over, and it is closed, and empty, the
iteration will end and not throw an error.

You can also bind channels to tasks, such that the channel will be automatically
closed when the task ends.

That was a lot of stuff - anyway, the point is that channels, because they can be
safely operated on by multiple threads, serve as a foundation for coordinating
multiple tasks.

## Useful, high-level patterns
#### Compute a bunch of data in parallel
The easiest thing here is to write a `@thread`ed loop that puts the result
of each task into a vector:

@@juliacode
```
result = Vector{MyType}(undef, length(data))
@threads for (i, data_i) in collect(enumerate(data))
    result[i] = some_computation(data_i)
end
```
@@

Note that we need to collect the `enumerate`, because `enumerate` currently
doesn't define `firstindex` needed by the `@threads` macro.

#### Lower-level parallelism
Whenever you have a function that computes several things that has no dependency
between them, like this:

@@juliacode
```
function foo()
    x = bar()
    y = qux() # no dependency on x
    z = baz() # no dep. on x or y
    return (x, y, z)
end
```
@@

You can run them in different tasks, like this:

@@juliacode
```
function foo()
    x = @spawn bar()
    y = @spawn qux()
    # baz runs in the current task, no need to spawn a new
    # task for that
    z = baz()
    return (fetch(x)::MyType, fetch(y)::MyType, z)
end
```
@@

However, do remember that the overhead associated with each task is up to five
microsecond, so the runtime of `bar` and `qux` must be longer for this pattern
to be a net benefit.

#### Parallel loop with one serial bottleneck
If you have an loop that _almost_ could have been be run in parallel, _except_
for one thread-unsafe operation, use the normal `@threads` pattern, and guard
the thread-unsafe operation behind a lock.
This is particularly easy with the `Base.Lockable` type (exported from Base in
Julia 1.12)

@@juliacode
```
cache = Base.Lockable(Dict())
@threads for data_i in data
    @lock cache maybe_res = get(cache[], data_i, nothing)
    result_i = if isnothing(maybe_res)
        result_i = some_computation(data)
        @lock cache[][data_i] = result_i
    else
        maybe_res
    end
    # Do something with result_i
end
```
@@

#### Packages for async
The package OhMyThreads.jl provide nice high-level APIs for working with tasks.
"""

# ╔═╡ a305ee04-498a-4933-a813-8550f50a761d
md"""
## The future of async in Julia
Async has been an area of intense development in Julia since shortly after version
1.0. It was deemed a priority to flesh out async quickly after 1.0, because it was
feared that in the absence of async, the ecosystem might begin to rely too much
on syncronicity, making async harder to add later.
Even though the most important work on ay=sync has already been done, there are still
a few areas that the core developers seek to improve:

### Inference in tasks
Currently, Julia can't do inference across tasks. That implies that e.g. `fetch`
is always inferred as `Any`. This is obviously annoying, and it'd be much nicer
if Julia had inter-task inference on the same level as inter-function inference.

### Better multithreaded garbage collection
As previously mentioned, having a stop-the-world garbage collector currently creates problems
with concurrent workloads.
There are several ways the situation could be improved in the future:

* An entirely new garbage collector design, which requires less syncronization
  between individual threads, such as the recently added
  [non-moving immix GC](https://github.com/JuliaLang/julia/pull/56288)
  could reduce the need for stopping the world.

* The Julia compiler could gain an understanding of when a function allocates.
  A function that doesn't allocate, or only allocates in a foreign function call,
  does not need to be stopped for the GC to run.

### Various optimisation
Many of the important moving parts has not been thoroughly optimised.
In particular, the core devs have long talked about making the `Task` objects
faster and more memory efficent to create.
The scheduler itself could also be optimised, and so could locks.

## TODO:
Some things like IO and sleep callback can only run on thread 1. So if that doesn't yield and can't yield, your system may freeze.
"""

# ╔═╡ 7c750b87-b513-4a1b-9a4e-b4dea6651ed0
md"""## TODO
* False sharing
* Atomics
* Semaphore
* Design space:
* Why not just use OS threads?
    - Faster than the OS shcedular
    - POtential for inter-task optimisation in the same runtime and other optimisations
    - Allows us to control scheduling, e.g. giving more frequent time to tasks that must
      be responsive like a task checking for user input
* Green threading: Namedrop
* One stack, more smaller, growable? Or keep multiple tasks on single stack?
"""

# ╔═╡ 00000000-0000-0000-0000-000000000001
PLUTO_PROJECT_TOML_CONTENTS = """
[deps]
PlutoUI = "7f904dfe-b85e-4ff6-b463-dae2292396a8"

[compat]
PlutoUI = "~0.7.60"
"""

# ╔═╡ 00000000-0000-0000-0000-000000000002
PLUTO_MANIFEST_TOML_CONTENTS = """
# This file is machine-generated - editing it directly is not advised

julia_version = "1.11.3"
manifest_format = "2.0"
project_hash = "8aa109ae420d50afa1101b40d1430cf3ec96e03e"

[[deps.AbstractPlutoDingetjes]]
deps = ["Pkg"]
git-tree-sha1 = "6e1d2a35f2f90a4bc7c2ed98079b2ba09c35b83a"
uuid = "6e696c72-6542-2067-7265-42206c756150"
version = "1.3.2"

[[deps.ArgTools]]
uuid = "0dad84c5-d112-42e6-8d28-ef12dabb789f"
version = "1.1.2"

[[deps.Artifacts]]
uuid = "56f22d72-fd6d-98f1-02f0-08ddc0907c33"
version = "1.11.0"

[[deps.Base64]]
uuid = "2a0f44e3-6c83-55bd-87e4-b1978d98bd5f"
version = "1.11.0"

[[deps.ColorTypes]]
deps = ["FixedPointNumbers", "Random"]
git-tree-sha1 = "b10d0b65641d57b8b4d5e234446582de5047050d"
uuid = "3da002f7-5984-5a60-b8a6-cbb66c0b333f"
version = "0.11.5"

[[deps.CompilerSupportLibraries_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "e66e0078-7015-5450-92f7-15fbd957f2ae"
version = "1.1.1+0"

[[deps.Dates]]
deps = ["Printf"]
uuid = "ade2ca70-3891-5945-98fb-dc099432e06a"
version = "1.11.0"

[[deps.Downloads]]
deps = ["ArgTools", "FileWatching", "LibCURL", "NetworkOptions"]
uuid = "f43a241f-c20a-4ad4-852c-f6b1247861c6"
version = "1.6.0"

[[deps.FileWatching]]
uuid = "7b1f6079-737a-58dc-b8bc-7a2ca5c1b5ee"
version = "1.11.0"

[[deps.FixedPointNumbers]]
deps = ["Statistics"]
git-tree-sha1 = "05882d6995ae5c12bb5f36dd2ed3f61c98cbb172"
uuid = "53c48c17-4a7d-5ca2-90c5-79b7896eea93"
version = "0.8.5"

[[deps.Hyperscript]]
deps = ["Test"]
git-tree-sha1 = "179267cfa5e712760cd43dcae385d7ea90cc25a4"
uuid = "47d2ed2b-36de-50cf-bf87-49c2cf4b8b91"
version = "0.0.5"

[[deps.HypertextLiteral]]
deps = ["Tricks"]
git-tree-sha1 = "7134810b1afce04bbc1045ca1985fbe81ce17653"
uuid = "ac1192a8-f4b3-4bfe-ba22-af5b92cd3ab2"
version = "0.9.5"

[[deps.IOCapture]]
deps = ["Logging", "Random"]
git-tree-sha1 = "b6d6bfdd7ce25b0f9b2f6b3dd56b2673a66c8770"
uuid = "b5f81e59-6552-4d32-b1f0-c071b021bf89"
version = "0.2.5"

[[deps.InteractiveUtils]]
deps = ["Markdown"]
uuid = "b77e0a4c-d291-57a0-90e8-8db25a27a240"
version = "1.11.0"

[[deps.JSON]]
deps = ["Dates", "Mmap", "Parsers", "Unicode"]
git-tree-sha1 = "31e996f0a15c7b280ba9f76636b3ff9e2ae58c9a"
uuid = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"
version = "0.21.4"

[[deps.LibCURL]]
deps = ["LibCURL_jll", "MozillaCACerts_jll"]
uuid = "b27032c2-a3e7-50c8-80cd-2d36dbcbfd21"
version = "0.6.4"

[[deps.LibCURL_jll]]
deps = ["Artifacts", "LibSSH2_jll", "Libdl", "MbedTLS_jll", "Zlib_jll", "nghttp2_jll"]
uuid = "deac9b47-8bc7-5906-a0fe-35ac56dc84c0"
version = "8.6.0+0"

[[deps.LibGit2]]
deps = ["Base64", "LibGit2_jll", "NetworkOptions", "Printf", "SHA"]
uuid = "76f85450-5226-5b5a-8eaa-529ad045b433"
version = "1.11.0"

[[deps.LibGit2_jll]]
deps = ["Artifacts", "LibSSH2_jll", "Libdl", "MbedTLS_jll"]
uuid = "e37daf67-58a4-590a-8e99-b0245dd2ffc5"
version = "1.7.2+0"

[[deps.LibSSH2_jll]]
deps = ["Artifacts", "Libdl", "MbedTLS_jll"]
uuid = "29816b5a-b9ab-546f-933c-edad1886dfa8"
version = "1.11.0+1"

[[deps.Libdl]]
uuid = "8f399da3-3557-5675-b5ff-fb832c97cbdb"
version = "1.11.0"

[[deps.LinearAlgebra]]
deps = ["Libdl", "OpenBLAS_jll", "libblastrampoline_jll"]
uuid = "37e2e46d-f89d-539d-b4ee-838fcccc9c8e"
version = "1.11.0"

[[deps.Logging]]
uuid = "56ddb016-857b-54e1-b83d-db4d58db5568"
version = "1.11.0"

[[deps.MIMEs]]
git-tree-sha1 = "65f28ad4b594aebe22157d6fac869786a255b7eb"
uuid = "6c6e2e6c-3030-632d-7369-2d6c69616d65"
version = "0.1.4"

[[deps.Markdown]]
deps = ["Base64"]
uuid = "d6f4376e-aef5-505a-96c1-9c027394607a"
version = "1.11.0"

[[deps.MbedTLS_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "c8ffd9c3-330d-5841-b78e-0817d7145fa1"
version = "2.28.6+0"

[[deps.Mmap]]
uuid = "a63ad114-7e13-5084-954f-fe012c677804"
version = "1.11.0"

[[deps.MozillaCACerts_jll]]
uuid = "14a3606d-f60d-562e-9121-12d972cd8159"
version = "2023.12.12"

[[deps.NetworkOptions]]
uuid = "ca575930-c2e3-43a9-ace4-1e988b2c1908"
version = "1.2.0"

[[deps.OpenBLAS_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "Libdl"]
uuid = "4536629a-c528-5b80-bd46-f80d51c5b363"
version = "0.3.27+1"

[[deps.Parsers]]
deps = ["Dates", "PrecompileTools", "UUIDs"]
git-tree-sha1 = "8489905bcdbcfac64d1daa51ca07c0d8f0283821"
uuid = "69de0a69-1ddd-5017-9359-2bf0b02dc9f0"
version = "2.8.1"

[[deps.Pkg]]
deps = ["Artifacts", "Dates", "Downloads", "FileWatching", "LibGit2", "Libdl", "Logging", "Markdown", "Printf", "Random", "SHA", "TOML", "Tar", "UUIDs", "p7zip_jll"]
uuid = "44cfe95a-1eb2-52ea-b672-e2afdf69b78f"
version = "1.11.0"

    [deps.Pkg.extensions]
    REPLExt = "REPL"

    [deps.Pkg.weakdeps]
    REPL = "3fa0cd96-eef1-5676-8a61-b3b8758bbffb"

[[deps.PlutoUI]]
deps = ["AbstractPlutoDingetjes", "Base64", "ColorTypes", "Dates", "FixedPointNumbers", "Hyperscript", "HypertextLiteral", "IOCapture", "InteractiveUtils", "JSON", "Logging", "MIMEs", "Markdown", "Random", "Reexport", "URIs", "UUIDs"]
git-tree-sha1 = "eba4810d5e6a01f612b948c9fa94f905b49087b0"
uuid = "7f904dfe-b85e-4ff6-b463-dae2292396a8"
version = "0.7.60"

[[deps.PrecompileTools]]
deps = ["Preferences"]
git-tree-sha1 = "5aa36f7049a63a1528fe8f7c3f2113413ffd4e1f"
uuid = "aea7be01-6a6a-4083-8856-8a6e6704d82a"
version = "1.2.1"

[[deps.Preferences]]
deps = ["TOML"]
git-tree-sha1 = "9306f6085165d270f7e3db02af26a400d580f5c6"
uuid = "21216c6a-2e73-6563-6e65-726566657250"
version = "1.4.3"

[[deps.Printf]]
deps = ["Unicode"]
uuid = "de0858da-6303-5e67-8744-51eddeeeb8d7"
version = "1.11.0"

[[deps.Random]]
deps = ["SHA"]
uuid = "9a3f8284-a2c9-5f02-9a11-845980a1fd5c"
version = "1.11.0"

[[deps.Reexport]]
git-tree-sha1 = "45e428421666073eab6f2da5c9d310d99bb12f9b"
uuid = "189a3867-3050-52da-a836-e630ba90ab69"
version = "1.2.2"

[[deps.SHA]]
uuid = "ea8e919c-243c-51af-8825-aaa63cd721ce"
version = "0.7.0"

[[deps.Serialization]]
uuid = "9e88b42a-f829-5b0c-bbe9-9e923198166b"
version = "1.11.0"

[[deps.Statistics]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "ae3bb1eb3bba077cd276bc5cfc337cc65c3075c0"
uuid = "10745b16-79ce-11e8-11f9-7d13ad32a3b2"
version = "1.11.1"

    [deps.Statistics.extensions]
    SparseArraysExt = ["SparseArrays"]

    [deps.Statistics.weakdeps]
    SparseArrays = "2f01184e-e22b-5df5-ae63-d93ebab69eaf"

[[deps.TOML]]
deps = ["Dates"]
uuid = "fa267f1f-6049-4f14-aa54-33bafae1ed76"
version = "1.0.3"

[[deps.Tar]]
deps = ["ArgTools", "SHA"]
uuid = "a4e569a6-e804-4fa4-b0f3-eef7a1d5b13e"
version = "1.10.0"

[[deps.Test]]
deps = ["InteractiveUtils", "Logging", "Random", "Serialization"]
uuid = "8dfed614-e22c-5e08-85e1-65c5234f0b40"
version = "1.11.0"

[[deps.Tricks]]
git-tree-sha1 = "6cae795a5a9313bbb4f60683f7263318fc7d1505"
uuid = "410a4b4d-49e4-4fbc-ab6d-cb71b17b3775"
version = "0.1.10"

[[deps.URIs]]
git-tree-sha1 = "67db6cc7b3821e19ebe75791a9dd19c9b1188f2b"
uuid = "5c2747f8-b7ea-4ff2-ba2e-563bfd36b1d4"
version = "1.5.1"

[[deps.UUIDs]]
deps = ["Random", "SHA"]
uuid = "cf7118a7-6976-5b1a-9a39-7adc72f591a4"
version = "1.11.0"

[[deps.Unicode]]
uuid = "4ec0a83e-493e-50e2-b9ac-8f72acf5a8f5"
version = "1.11.0"

[[deps.Zlib_jll]]
deps = ["Libdl"]
uuid = "83775a58-1f1d-513f-b197-d71354ab007a"
version = "1.2.13+1"

[[deps.libblastrampoline_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "8e850b90-86db-534c-a0d3-1478176c7d93"
version = "5.11.0+0"

[[deps.nghttp2_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "8e850ede-7688-5339-a07c-302acd2aaf8d"
version = "1.59.0+0"

[[deps.p7zip_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "3f19e933-33d8-53b3-aaab-bd5110c3b7a0"
version = "17.4.0+2"
"""

# ╔═╡ Cell order:
# ╠═8b83e436-dc12-11ef-1b27-1d3fdefb24c1
# ╠═21b2cbda-17d6-4466-adbc-5e513482e1af
# ╠═b278c476-74e9-4399-a05c-7c15111bfd3c
# ╠═17ddbb08-cd8d-446e-b806-dc3000dc2184
# ╠═8f6cf27f-5648-40ab-b029-d52c0eaf3883
# ╠═2bd97906-edc8-48e8-ac2d-6a87a2e01fe5
# ╠═af3b6b92-d1a1-43de-a88b-605f559e1d68
# ╠═c4f33908-efab-4654-b9dd-b4e46573428a
# ╠═5e45c378-3788-484c-906b-86586c8cd7c8
# ╠═a8acd763-7068-4a2c-9dd9-8f926680f8b7
# ╠═de1f77c2-bdbb-4192-ba24-da41489c0a8b
# ╠═f74b1284-dece-4216-bb06-29514415ff5f
# ╠═ef36118e-2fdf-4c99-a9da-f8cbc6885fb3
# ╠═67664ef0-0f00-4388-a47c-9d97d7b443a5
# ╠═0f800d3f-34ae-4f6c-b6bc-d7c82c1c1af2
# ╠═20ee5cfa-b80c-4a2f-8314-67048c1c429b
# ╠═a279c000-2154-44b9-bb72-41862b61fcbc
# ╠═0668560d-d2ff-49ae-a5ae-3a92ba269e53
# ╠═a40cd157-fde1-49be-9156-0b8caa12e5a5
# ╠═fc99d8b6-9b32-46a4-bde0-9108b029e43e
# ╠═602c3a65-79c2-4e6b-a70d-c9b3c1df20ca
# ╠═592fc034-8344-4cb7-b378-6ced7205ad9e
# ╠═a5fa1503-5880-4d0e-aba8-0c3ee34b6dfa
# ╠═422c8758-e0f6-491e-ad0d-743f4d9e7c48
# ╠═107291d1-1c00-45a7-9225-be541ff44ab6
# ╠═4266d974-0dca-4798-9952-2a7e8c77968c
# ╠═6a1c5924-92b6-40ef-967f-494332ade500
# ╠═718eac91-b4d1-4dee-ac67-76e4cb8ef341
# ╠═fde5713b-2774-43dc-90d1-36b1446d4540
# ╠═19609694-3c8e-4b46-be18-63011e315308
# ╠═9fe22bc2-2c4a-423d-85cb-60a16ad68ea3
# ╠═00e9e859-3238-41f8-93ca-b2243495083b
# ╠═b74ae921-f376-4a40-b042-4e7a777902ef
# ╠═65fc3a2d-de89-4cc2-8f1e-dbc2f90c416d
# ╠═a08bd0d6-776e-46a7-a186-614cc0bbd65d
# ╠═fd87476d-b32b-4785-9fdc-21da66b9adaa
# ╠═27133bd1-433e-4bc4-ac6e-c06b9c245b6e
# ╠═58b98795-03ad-44e7-ab68-cc5e4e397108
# ╠═e07e174d-3719-4025-91aa-f56365a68453
# ╠═d11037b5-241d-4878-9602-0043bb21e72b
# ╠═96d968b3-4662-4985-9a81-7fe6cdcbb524
# ╠═2a383feb-22d8-48d8-b247-c20ec5bbe91b
# ╠═1d70bc25-b941-4481-8579-80b70e7b6846
# ╠═6b900c42-127e-463f-b941-c321297537f3
# ╠═725773df-24c7-4547-84fc-3cd163d19136
# ╠═5688d79a-0593-4722-b4f6-252b327746b2
# ╠═a0ed20e1-da3f-4dbc-83b1-1399f0dea805
# ╠═a305ee04-498a-4933-a813-8550f50a761d
# ╠═7c750b87-b513-4a1b-9a4e-b4dea6651ed0
# ╟─00000000-0000-0000-0000-000000000001
# ╟─00000000-0000-0000-0000-000000000002
