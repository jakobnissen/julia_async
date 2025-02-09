### A Pluto.jl notebook ###
# v0.20.4

using Markdown
using InteractiveUtils

# ╔═╡ 21b2cbda-17d6-4466-adbc-5e513482e1af
# Import some packages
begin
    using PlutoUI
	using BenchmarkTools
end

# ╔═╡ 8f6cf27f-5648-40ab-b029-d52c0eaf3883
using .Threads

# ╔═╡ 8b83e436-dc12-11ef-1b27-1d3fdefb24c1
md"""
# Asynchronous programming in Julia
_Written 2025-02-08_

**This notebook is hosted at viralinstruction.com**

**Find the source code at https://github.com/jakobnissen/julia_async**

When I read blogs or textbooks on programming, I'm struck by the diversity of vantage points from which people think about our craft.
A lot of blogs describe their programming as revolving around websites and networks, where themes like communication protocols and JavaScript frameworks play major roles.
In my eight years of scientific programming, I've never had to think about any of that stuff. To me, that's like a parallel universe of software which interacts very little with what I do, or care about, on my job.

Most of the blogs I read mention asynchronous programming in this context of 'websites coding'. So, I thought that async was mostly about how your program handled waiting for network data.
An important subject, perhaps, but surely something I could ignore as a scientist.

Oh boy, was that wrong.

In this notebook, I'll dig into asynchronous programming in Julia.
I will begin with the most fundamental building blocks of async, and build up towards the more human-friendly high level async interfaces.

Let's begin.
"""

# ╔═╡ 0746182a-2e0e-4bc3-a8e5-459b8a7a6f28
# Make sure any benchmarking cells don't take too long
# to execute. Two seconds per cell should be enough.
BenchmarkTools.DEFAULT_PARAMETERS.seconds = 2;

# ╔═╡ b278c476-74e9-4399-a05c-7c15111bfd3c
TableOfContents()

# ╔═╡ 17ddbb08-cd8d-446e-b806-dc3000dc2184
md"""
## Why is async important?
Asynchronous programming means having different parts of your program in progress at the same time, although, as we will see, the meaning of "the same time" is elusive.

To do this, the programming language needs to somehow abstract over 'units of computation' as separate _tasks_ that can be started, paused, restarted and stopped.

In Julia, this is fittingly modelled with the `Task` type.
Tasks are most easily created with the `Threads.@spawn` macro, which will wrap a Julia expression in a zero-argument function, and then run that function as a task:
"""

# ╔═╡ 2bd97906-edc8-48e8-ac2d-6a87a2e01fe5
task = @spawn begin
	x = 1 + 1
	return x + 1
end

# ╔═╡ c4f33908-efab-4654-b9dd-b4e46573428a
md"""
Tasks are first _created_, then _started_, after which they can be _paused_ and _resumed_ an arbitrary amount of times during their lifetime.
When the function they wrap returns, the task is _done_.
If the function in the task throws an unhandled exception, the task has _failed_.
Failed and done tasks cannot be restarted.

To wait for the completion of a task and obtain its return value, use `fetch`. 
"""

# ╔═╡ 5e45c378-3788-484c-906b-86586c8cd7c8
fetch(task)

# ╔═╡ a8acd763-7068-4a2c-9dd9-8f926680f8b7
md"""
The most common (but not _only_!) use case for tasks is to allow _parallel computation_, where multiple tasks are running at the same time.

The difference between asynchronous and parallel programming is that parallel programming explicitly means that multiple tasks are running at once. Async programming is a broader term that includes parallel programming, but also includes situations where execution switches between tasks but only one runs at any given time.

    >>>>>>>>>>>>>>>>>>>>>>> Time >>>>>>>>>>>>>>>>>
    Async but not parallel    
      Task A ----->          ---->         -->
      Task B       --------->     -------->   -->

    Async and parallel
      Task A ------------------------------------>
      Task B ------------------------------------>

When tasks are started, they run on an underlying _thread_ provided by the operating system.
The total number of threads currently needs to be set from command line when starting Julia using the command-line flag `--threads` (or `-t`, for short).
It's the job of the operating system to distribute hardware resources (e.g. CPU time) among the threads.

A CPU core can only run one or two threads at a time, so the number of threads are usually a small, fixed number corresponding to the core count of the CPU.
You can check the number of current threads with the function `Threads.nthreads()`:
"""

# ╔═╡ de1f77c2-bdbb-4192-ba24-da41489c0a8b
Threads.nthreads()

# ╔═╡ f74b1284-dece-4216-bb06-29514415ff5f
md"""
Julia intentionally provide few abstractions to interact with the threads themselves, focusing instead on _tasks_ as the central unit of asynchronous computing.
As a programmer, your focus is supposed to be on managing the tasks, and you can usually simply rely on Julia to do a reasonable job of running the tasks on all available threads in an efficient manner.

Precisely because the user is not supposed to think about threads, Julia has great freedom in which tasks are run on what threads.
At least abstractly, a task may be run on any available thread, started and stopped arbitrarily, and even moved between threads.
"""

# ╔═╡ ef36118e-2fdf-4c99-a9da-f8cbc6885fb3
md"""
To whet our appetite, let's demonstrate a toy use of tasks to achieve asynchrony.
One of the most basic design patterns is to spawn and fetch tasks within a single function. For example, in the following case: 
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
In `complex_function`, the calls to the two 'simple functions' do not depend on each other, and may be run in any order. Hence, we can run one of them as a separate task, which then runs in the background while the other simple function is executed. In principle, this pattern can double the speed of a function with the same structure as `complex_function`.

At the time of writing, Julia unfortunately cannot do type inference on `fetch` which always infers to `Any`.
Hopefully, that will be fixed in the near future.
Until then, I recommend you annotate the return value of `fetch` with the expected return type to obtain type stability.
"""

# ╔═╡ 20ee5cfa-b80c-4a2f-8314-67048c1c429b
md"""
## The law of async
Since async is all about splitting your program into stoppable and resumable tasks, converting synchronous code to asynchronous can be an invasive exercise, in that it may reorganize your entire program.
Async code is also (deservedly) infamous for being tricky to reason about and prone to bugs.
To reduce the risk of bugs, it helps to internalize the cental law of async:

> Mutation requires exclusivity

That is, if one task mutates some data, no other task must access that data (read from or write to it) at the same time.
The reason is that most code relies on the assumption that data doesn't spontaneously change while it's being operated on.
If task A mutates some data while task B operates on it, from the point of view of task B, the data _does_ appear to spontaneously mutate.

In this spirit of legalism, let's write some sections of this law:

§ 1a. The different elements of an `Array` are considered different data.
  That is, it's allowed for two tasks to mutate or operate on
  different elements concurrently.

§ 1b. Some operations appear to only affect one element of an array, but
  actually affects all of them. E.g. `push!` might cause the whole array
  to be resized, which requires copying the memory of the whole array.
  Therefore, such an operation counts as mutating _every_ element.
  Similarly, in Julia, the elements of `BitArray` are not independent:
  Because multiple bits are stored in the same integer in an underlying `Array`        in the bitarray,
  mutating one element of the array actually mutates the whole integer,
  which affects multiple elements in the `BitArray`

§ 1c. If no task is mutating a piece of data, then it may be shared freely
  among tasks. For example, multiple tasks may look up in the same
  dict, or copy the same string, concurrently.
"""

# ╔═╡ a279c000-2154-44b9-bb72-41862b61fcbc
md"""
## Data races

Let's have a look at an example of what happens when you violate the law of async.

In the code below, `add_ten_million!` will increment an integer through a reference ten million times. The function `increment_occasionally` will read the same reference, add its content to a result, and then substracts the same number it added to the result from the reference.
You can envision this as modelling a task that records the current progress on some computation, and another task that occasionally displays the progress since the last update.

The code contains a function call to `Threads.atomic_fence`.
You can ignore this for now - I'll get back to it later.
"""

# ╔═╡ 0668560d-d2ff-49ae-a5ae-3a92ba269e53
function add_ten_million!(ref)
	for i in 1:10_000_000
		ref[] += 1
		atomic_fence() # ignore this function call for now
	end
end;

# ╔═╡ a40cd157-fde1-49be-9156-0b8caa12e5a5
function increment_occasionally(ref)
	t = time_ns()
	result = 0
	while time_ns() - t < 1_000_000_000
		increment = ref[]
		result += increment
		ref[] -= increment
		atomic_fence() # ignore this function call for now
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
The result is _non-deterministic_ - every time you run it, it's likely to give a different number.

The reason it doesn't behave as expected is that both tasks mutate `ref` concurrently, violating the law of async.
We call such situation _data races_.

In this particular example, the problem occurs because of the details of how the line `ref[] += 1` is implemented.
The line `ref[] += 1` is equivalent to `ref[] = ref[] + 1` - actually three operations in disguise:

1. Load `ref[]`
2. Add 1 to the loaded value
3. Store the result back into `ref[]`.

Suppose now `ref` has a value of 5, and task A runs `add_ten_million` thus incrementing `ref`, and task B runs `increment_occasionally` and thus zeros `ref`.
There is is some chance that it could be executed in the following order:

1. Task A loads `ref[]` getting 5
2. Task B computes `increment = ref[]`, getting 5
3. Task A computes `5 + 1`, getting 6
4. Task B subtracts 5 from `ref`, setting it to zero
5. Task A sets `ref` to 6

If that occurs, the subtraction done by task B will be cancelled when task A stores `6` back into ref, and therefore the 5 previous increments will be added twice to `result`.

Here, the underlying cause is that `ref[] += 1` is composed of several steps, and that the other task is able to read or modify data while it is in the middle of this series of steps.

In computer science terms, we say that the problem is that `ref[] += 1` is _not atomic_. Here, "atomic" is used in the original Greek sense, meaning _indivisible_.
An atomic operation is one that can never be observed is a state of partial completion - it either has not happened yet, or is already complete.

#### Even single CPU instructions are not atomic
It is tempting to try to solve data races like the one above by simply choosing operations which are not implemented in terms of multiple smaller operations.
But if you look into the generated assembly code for the `add_ten_million!` function above, you will see that the line `ref[] += 1` is compiled to a single instruction - at least on my computer with a x86-64 CPU.
So naively, one would think that this single instruction would be atomic - not composed of multiple, smaller steps. Nonetheless, the data race happened. Why?

In the CPU, even single CPU instructions may be executed in terms of smaller _micro-operations_, the details of which is an implementation detail of the CPU. Furthermore, the CPU's memory system is complex and multi-layered, and there is no guarantee that when a computer stores a value to memory, other parts of the CPU will immediately be able to see the stored value.

Finally, on the programming language level, while Julia might implement the increment as a single instruction right now, Julia provides no guarantee that the compiler will generate the same assembly code in the future, making it pointless to write code based on the exact assembly instructions that are generated.

This will be a recurring theme in this notebook: The rules of async are abstractions that can't easily be explained in terms of the underlying implementation, because the implementations are complex and opaque.
As a programmer, your best bet is to adhere to the abstraction and not try to outsmart it by peeking under the hood. 

Once we know that
1. All CPU operations may be split into multiple steps in the CPU and the memory hierarchy, and
2. Interacting with data that is in a partially processed state may cause a data race,

we find ourselves forced to conclude that two different tasks can never interact with the same data at all, and so the prospect of writing asynchronous code appear completely hopeless.

## Atomic operations
Fortunately, Julia provides dedicated _atomic operations_ to address this problem. The compiler guarantees that these operations are always compiled down to dedicated atomic CPU instructions, which the CPU in turn guarantees are actually atomic.

Let's try to solve the bug using atomic operations.
To use atomic operations in Julia, we need to use a mutable struct, with the relevant field marked `@atomic`:
"""

# ╔═╡ a5fa1503-5880-4d0e-aba8-0c3ee34b6dfa
mutable struct Atomic{T}
	@atomic x::T
end

# ╔═╡ 422c8758-e0f6-491e-ad0d-743f4d9e7c48
md"""
We can now rewrite the functions above, using this atomic integer in place of our old `Ref`.
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
		increment = @atomic atomic.x
		result += increment
		@atomic atomic.x -= increment
	end
	result
end;

# ╔═╡ 6a1c5924-92b6-40ef-967f-494332ade500
let
	atomic = Atomic{Int}(0)
	t = @spawn increment_occasionally_atomic(atomic)
	add_ten_million_atomic!(atomic)
	fetch(t) + @atomic atomic.x
end

# ╔═╡ 718eac91-b4d1-4dee-ac67-76e4cb8ef341
md"""
Voila! The bug disappeared.

## Memory re-ordering
Atomic operations have a _memory ordering_ associated with them.
To understand memory ordering, it is necessary to take a detour and look at how memory re-ordering happens in normal non-atomic code that is executed within a task.

### Re-ordering within a task
We begin by looking at the simple Julia function below:
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
As we know and love, the Julia compiler will make sweeping changes the code we've written in the name of optimisation.
For example, it may evaluate `b = 1 + 1` to `2` at compile time, then move this computation down onto the last line, such that it becomes `return a + 2`.
Similarly, it may delete the redundant `a = 1` line, since `a` will be overwritten immediately after, anyway.

But wait: If the compiler is allowed to _both_ shuffle around the code, _and_ delete redundant stores, why can't it reorder `a = 2` to come before `a = 1`, and then delete the now-redundant `a = 2` line instead?

The obvious answer is that the compiler must have a notion of _dependent data_: Computing `b` has no dependency on the computation of `a`, and so may be moved around freely with respect to `a`.
In contrast, `a = 1` and `a = 2` are dependent on each other, since they mutate the same variable.
Generally, data (i.e. a variable or a memory location) `A` depends on data `B` if `B` is being used to mutate `A`.

Dependent operations must have a notion of _happens before_, i.e. `a = 1` happens before `a = 2`, so these two lines can't just be rearranged with respect to each other.

Once again, I want to stress that _happens before_ is an __abstraction__.
In practice, the function `order1` will compile down to simply `return 4`, and when the program runs, there won't exist any data that corresponds to the variables `a` or `b`.
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

That may surprise you. After all, `b[] = a[]` is guaranteed to happen after `a[] = true`, since `b` depends on `a`.
Therefore, you would think, in `observe_overwrite`, if `b[]`, then `a[] = true` must have already happened, and therefore, `a[]` necessarily must return `true`.

Right?

Not so. What we missed with the above analysis is that, absent atomic operations, there is no notion of happens-before between tasks. So, the function `observe_overwrite` could observe the operations in `overwrite` in any order.
Remarkably, this includes the reality-warping order where `b` stores `true` __before__ `a` does, despite `b` supposedly loading its value from `a`!
Therefore, `observe_overwrite` could plausibly load `true` from `b[]`, and then return a `false` from `a[]`!

We can construct even more cursed situations where the lack of happens-before between tasks mean that one task will implicitly observe another task doing its operation in an absurd and seemingly impossible order.

We _could_ then try to explain why this can happen in terms of the complex underlying implementation in the CPU and memory hierarchy, but as I previously said, there's little point in trying to peek behind the curtain. Just use atomics when sharing data between tasks, or else you'll get bugs.

### Atomic memory orderings
It's important to keep in mind _why_ our compiler, CPU and memory re-order operations, making asynchronous code so damned hard to reason about: Speed.
Computers could be built perfectly synchronously with no out-of-order execution, but they would run tens, or hundreds of times slower.
The more we restrict out-of-order computation using atomics, the slower our program runs.
Ideally, we want to place only the exact amount of re-ordering restrictions to allow our async code to be correct, but no more.

Therefore, atomic operations come with a selection of _memory orderings_, such that we can pick the most lax ordering that allows some optimisations, while still making our program work correctly.

#### Ordering: Sequentially consistent
The default memory ordering, used if not explicitly specified, is also the strongest one: _sequentially consistent ordering_.
When a sequentially consistent operations happens, then
* All tasks are guaranteed to be able to observe it
* All tasks are guaranteed to also be able to see writes that occurred before the operation
* All tasks are guaranteed to not yet be able to observe writes that occur after the operation

In this way, a sequentially consistent operation acts like a memory barrier that imposes some order to inter-task operations: No operations can be re-ordered across the barrier, either in the before => after direction, nor in the after => before direction, no matter what task you are observing from.

We can fix the above example with a sequentially consistent operation:
If the observer task atomically reads `b.x` as `true`, the atomic operation `b.x = a[]` is fully completed, in which case `a[] = true` is guaranteed to have been completed due to the memory ordering guarantee of sequentially consistent.
"""

# ╔═╡ 65fc3a2d-de89-4cc2-8f1e-dbc2f90c416d
function overwrite_atomic(a::Ref{Bool}, b::Atomic{Bool})
	a[] = true
	# Sequentially consistent ordering is default,
	# so we could have omitted it here.
	
	# The memory ordering means that any task that observes `b`
	# to be true must also be able to observe a to be. 
	@atomic :sequentially_consistent b.x = a[]
end;

# ╔═╡ a08bd0d6-776e-46a7-a186-614cc0bbd65d
function observe_overwrite_atomic()
	a = Ref(false)
	b = AtomicBool(false)
	t = @spawn overwrite(a, b)
	(@atomic :sequentially_consistent b.x) ? a[] : true
end;

# ╔═╡ fd87476d-b32b-4785-9fdc-21da66b9adaa
md"""
The mysterious `atomic_fence()` function called in the data racey, non-atomic example above inserts a sequentially consistent memory fence, without doing any actual atomic operations.
It was needed in the first example to prevent Julia from being too clever and hoisting the increments outside the loop, thereby preventing a data race and foiling my example. 

#### Ordering: Monotonic (or relaxed)
At the opposite end from sequentially consistent ordering, we have the _monotonic_ ordering, also called _relaxed_ ordering in other languages.
This ordering provide _no restrictions_ on memory re-ordering, allowing the computer full freedom to re-order operations around for maximal performance.

Consider the example in `add_ten_million_atomic!`.
Here, we don't really care if the compiler moves around the atomic loads or stores, e.g. by unrolling the loop, or even by the compiler moving the atomic increments outside the loop, and switching the ten million atomic increments to a single atomic addition by ten million.

For this reason, that example would have been best solved by using monotonic atomic operations.
"""

# ╔═╡ 27133bd1-433e-4bc4-ac6e-c06b9c245b6e
md"""
#### Ordering: Acquire and release
It turns out, that, most of the time when we _do_ care about memory ordering, we don't require the kind of complete memory barrier that the sequentially consistent ordering provide.

One of the most common scenarios in async programming is when one task computes a value, then atomically modifies a flag to signal the value is ready to be read by another task.
Meanwhile, another task reads the flag, waiting for it to be changed before the task loads the value and continues processing it.

An example could look like this:
"""

# ╔═╡ e07e174d-3719-4025-91aa-f56365a68453
function mark_when_ready(is_ready, shared)
	sleep(0.2) # do some computation
	shared[] = 42
	@atomic :release is_ready.x = true
end;

# ╔═╡ d11037b5-241d-4878-9602-0043bb21e72b
function return_when_ready(is_ready, shared)
	while !(@atomic :acquire is_ready.x)
		# Only check once every 10 miliseconds
		sleep(0.01)
	end
	shared[]
end;

# ╔═╡ 2a383feb-22d8-48d8-b247-c20ec5bbe91b
md"""
Here, in `mark_when_ready`, it's crucial that no operations are moved from in the before => after direction across the atomic modification of `is_ready`.
For example, if `shared[] = 42` was moved to after the atomic operation, then the other task might use `shared` before it was ready.

But the opposite isn't true! It would be no problem if the compiler moved some non-atomic operations in the after => before direction across the atomic operation.

In `return_when_ready`, it's the opposite situation: `shared[]` cannot move in the after => before direction across the atomic load of `is_ready`, but it would not be a problem if there was some operation above the atomic load that was moved to after.

These kinds of situations are what the _acquire_ and _release_ orderings are used for: The release ordering is used for a write operation to release some data to another task, and the acquire ordering is used for a read operation to access data modified in another task.
They each create one-way memory barriers; release creates a before => after barrier, and acquire an after => before barrier.
"""

# ╔═╡ 606f9ce3-90f2-442c-aac7-d2a24a61f180
md"""
### Atomic swap
There are situations where atomic reads and atomic writes are not enough to ensure synchronization between threads.

The example below is similar to the previous example, but now two tasks are waiting to process the data at the same time - we can call these _consumer tasks_.
In this example there is no real need to have multiple tasks waiting since only one of them can do any work, but one could easily imagine that the consumer tasks process not one element, but a stream of data produced by the main producer task.

Here, we use an extra atomic boolean `is_done` to signal to the consumer tasks that they should stop waiting for the data to be ready:
"""

# ╔═╡ 69652455-0e9f-4b2a-bbef-464841dc9bc5
begin
	function use_data_when_ready(
		data::Ref{Int},
		is_ready::Atomic{Bool},
		is_done::Atomic{Bool},
	)
		# Check atomically if data is ready to be processed
		while !(@atomic :acquire is_ready.x)
			# If the other task already processed data, return
			(@atomic :acquire is_done.x) && return nothing
			# Only check once every 1 millisecond
			sleep(0.001)
		end
		# Signal other task should not process the data,
		# but should instead exit
		@atomic :release is_ready.x = false
		@atomic :release is_done.x = true
		println(data[]) # Process data
	end

	function run_example()
		data = Ref(0)
		is_ready = Atomic{Bool}(false)
		is_done = Atomic{Bool}(false)
		# Spawn two tasks to process the data
		tasks = map(1:2) do _
			@spawn use_data_when_ready(data, is_ready, is_done)
		end
		sleep(0.1)
		data[] = 1
		@atomic :release is_ready.x = true
		foreach(fetch, tasks) # wait for tasks
		return nothing
	end
end;

# ╔═╡ 175bc3f1-1a25-4d0a-b454-44b34b5efe11
run_example()

# ╔═╡ f2f2e703-9874-4872-958b-d653f9a8365a
md"""
The above example has a synchronization bug. Can you spot it?

It is possible for the two consumer tasks to simultaneously read `is_ready` and break out of the while loop, before either of them is able to set `is_ready.x = false` to disable the other task. It's unlikely, but absolutely possible.

The underlying problem is that, while both the read from, and the write to `is_ready` are individual atomic operations, that's not enough in this example.
It will cause issues if task B reads reads `is_ready` in between task A reading and writing it. 
What we need here is to do _both_ the reading and the writing as one single atomic operation.

For this, we can use the `@atomicswap` macro. This sets a field and reads the old value in one atomic operation.
In most other programming languages, atomic swap is called _atomic exchange_.

We can use this to rewrite the while loop in the example above like so:

```julia
while !(@atomicswap :sequentially_consistent is_ready.x = false)
	(@atomic :acquire is_done.x) && return nothing
	sleep(0.001)
end
```

This will _guarantee_ that, if `is_ready` is only set to `true` once, then only one of the tasks will break out of the while loop.
"""

# ╔═╡ 9d335a94-9b57-4624-a0f0-b54829a951e5
md"""
#### Ordering: Acquire-release
In the `@atomicswap` example above, I used the sequentially consistent memory ordering. This is because we need both the read and the write to be atomic at the same time, and the acquire and release orderings are only for reads and writes, respectively.

In reality, this is exactly the kind of situation where the _acquire-release_ ordering is supposed to be used. This ordering provides both the guarantees of the acquire ordering and the release ordering.

So, if acquire-release both places a memory barrier in the before => after direction (like `:release` provides) and an after => before barrier like `:acquire`, what is then the difference from sequentially consistent?

Honestly, I still don't understand. Apparently, sequentially consistent is even more strict than acquire-release, because only sequentially consistent operations are guaranteed to be part of a global, total modification order - whatever that means.
"""

# ╔═╡ fc8d9128-9788-416f-b387-575c87e73360
md"""
### Atomic replace
The most advanced operation operations are the _atomic replace_ operations, also called _atomic compare and swap_, or _atomic compare and exchange_.

An atomic replace is like a conditional swap: The value is swapped, but only if the old value was equal to some expected value.

In Julia, the macro `@atomicreplace atomic.fieldname expected => new` works just like the below function, except that it does everything in a single, atomic operation:


```julia
function atomic_replace(atomic, fieldname, expected, new)
	old = getfield(atomic, fieldname)
	success = old == expected
	if success
		setfield!(atomic, fieldname, new)
	end
	return (; old, success)
end
```

These operations take _two_ memory orderings: One to be followed if the swap is successful, and another if the swap failed.

Atomic replace is used, for example, to atomically increment or decrement an integer.
In Julia, the atomic operation `@atomic x.x += i` is rewritten by the compiler to a while loop using atomic swap, similar to this below:
"""

# ╔═╡ 62b369f9-15f7-4737-8dda-40211f8f22c0
function atomic_add(x::Atomic{Int}, i::Int)
	while true
		old = @atomic :monotonic x.x
		if (@atomicreplace x.x old => old + i).success
			return old + i
		end
	end
end;

# ╔═╡ c82ec1aa-dd68-42e1-9ff0-1e1222c916f3
md"""
The while loop is necessary, becaue another task might change `x` between `old + i` is computed and the atomic replace occurs. If that happens, then the atomic replace will fail because the atomic is no longer the expected value `old`, and the loop will restart.
The loop will only break if either `x` is not modified between the two atomic operations, or it's modified by e.g. incrementing and decrementing by one, such that the value of `x` is unchanged.
Therefore, even though this is an whole while loop, it acts atomically when viewed from the outside.
"""

# ╔═╡ 69b86287-ad33-486a-9b70-b4eacb443f43
md"""
### Atomics are mostly used to implement other async abstractions
Atomic operations provide the lowest level abstractions for async, being essentially async-friendly single CPU instructions.

They aren't exactly user friendly though. Not only because of their low level, but also because their memory ordering and happens-before relationship is tricky to reason about.

Direct use of atomics can also be extremely _inefficient_.
For example, the `return_when_ready` function implemented above will continuously check whether the shared value is ready, consuming CPU cycles in the process.
It would be much better if the function instead could be paused and only resumed once the value was ready.

In practice, most use cases of async don't directly use atomics, but will instead control tasks through  more user-friendly higher level abstractions implemented in terms of atomic operations.

Before we turn to those abstractions, let's look at what makes up a task itself.
"""

# ╔═╡ 1d70bc25-b941-4481-8579-80b70e7b6846
md"""
## Tasks and task switching
In order to be suspended and resumed, a task needs to keep track of its current progress. The progress of a task, or its state, is comprised of two parts:

First, the current state of the CPU registers. If the compiler statically knows all the points in the code where a task can be suspended, the compiler may make sure only a small subset of the registers are in use at that time, such that the task needs to store less state.
As we will see, in Julia, when Julia tasks yields control to other tasks, it's always voluntary, and so the compiler is able to do this optimisation.

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

In Julia, tasks carry their own independent stack. That makes them easier to work with, but makes them cost around 16 KiB memory to instantiate.
"""

# ╔═╡ 6b900c42-127e-463f-b941-c321297537f3
md"""
### How does task switching work?
Conceptually _and_ implementation wise, there are several similarities between
a _function call_ and a _task switch_.
At a function call, the CPU will pause the execution of the current function and
give control to a different piece of code, which is then automatically returned to
when the function returns. The parallels to task switching are obvious.

So: How do function calls work?

In x86-64 CPUs, the rip (register instruction pointer) register stores
the memory location of the next instruction to be executed by the CPU.
To begin executing a function, we need to change the value of this register to
point to the first instructions of our callee.
Changing the value of the rip register is done with a _jump_ instruction -
i.e. we say that the program jumps to some memory location.
However, first, the CPU needs to make sure it can resume the work when the callee
returns.

By convention, on Linux on x86-64 computers, the seven registers rsp, rbx, rbp,
and r12-r15 are so-called _callee saved_. This means that no function is allowed
to change these registers when being called: Either they must leave the registers
alone, or else they must make sure to push the original state of the registers to
the stack, and pop them from the stack back into the registers, in order to restore
them, before returning.

Therefore, any _caller_ can assume no callee changes these registers, and can store
information in them. Any state that can't be kept in these registers are pushed to the stack.
Aside from the callee saved registers, the CPU only needs to store the aforementioned rip register on the stack, in order to be able to return the execution to where it left off, and thus fully restore the CPU state.

So, to call a function, the CPU needs to:
1. Store all local state in either the seven callee-saved registers or on the stack,
2. Push the rip register to the stack, to save the exact location where the call happened, such that the code can jump back to the location upon function return
3. Move the memory location of the callee into the rip register

The `call` assembly instruction will do the last two points and comprise the actual function call itself.

When the callee has been executed, and control needs to return to the caller,
this is what needs to happen:

1. Clean up the stack by popping any data off it, such that it's in the same state
   the callee found it in
2. Pop the stack into the rip register. Since the last element on the stack placed
   by the caller was the rip register, doing this returns execution to the instruction
   immediately after `call` in the caller, and allows the caller to continue executing.

The `ret` instruction will pop the last element of the stack into the rip register, thus returning from the function.

We can use the same general approach when switching tasks:
When a task gives away control to another task,
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

Instead, a program called the _scheduler_ keeps track of all tasks in the process.
The scheduler is a C program that is part of the Julia runtime, similar to the garbage collector.
Having a single centralized program to control task switches makes things much easier for the programmer: Every task simply switches to the scheduler, which controls which task to switch to next.
If the Julia process has multiple threads, the scheduler may run multiple tasks in parallel.

User code may switch to the scheduler explicitly with the `yield` function.
More commonly, yields are built into a number function calls in Julia:
* Memory allocation, including during dynamic dispatch will occasionally yield
* Interaction with outside sources, like IO will usually yield
* Many operations on tasks and async-friendly data structures will yield

#### Blocking and non-blocking IO
When a Julia program needs access to your computer's resources, such as when opening a file, Julia needs to interact with the operating system to request them.
Especially for IO-related resources like the file system and network data, they may not be immediately available. What's the rational thing to do then?

Here, we distinguish between _blocking_ and _non-blocking_ operations. When executing a blocking operation, the program will halt and wait for the resource to be available, before progressing. In contrast, a non-blocking operation will return some kind of object representing a soon-to-be-available resource, and immediately return. The code can then intermittently check the object whether the resource has become available yet, and switch to other tasks to do useful work in the meantime.

This is the reason that async is often mentioned in the context of network programming: Networks often have significant latency, so even with only a single thread available, several tasks can often be run concurrently.

In Julia, all IO is non-blocking _from OS' point of view_, in the sense that the OS, when a resource is requested, will return control back to the Julia scheduler immediately and alert the scheduler when the resource is available.
However, from the point of view of a _Julia task_, IO is always blocking, in the sense that the scheduler will make sure to not schedule the task that requested the resource until the resouce is ready.

Therefore, in Julia lingo, when we talk about a blocking operation, we refer to an operation which yields control to the scheduler, and where the scheduler won't reschedule the task until the blocking operation is ready to proceeed.
We will return to various blocking operations later in this notebook.
"""

# ╔═╡ 766372a3-fb2c-4e86-8916-37bcaf9c0d79
md"""
### The Julia scheduler and the OS scheduler
The purpose of the Julia scheduler is to run Julia tasks on the limited number of threads provided by the operating system. 
Your operating system (OS) also has a scheduler, whose analogous job it is to map threads only the limited number of CPU cores provided by the hardware.

This raises a question: If the OS _already_ has a scheduler which maps an arbitrary number of threads onto your CPU cores, why does Julia even bother with a scheduler itself? Why doesn't every task simply spawn an OS level thread, and then let the OS efficiently manage the threads?

As usual, the reason is efficiency. The OS scheduler needs to keep more state related to each thread, including the per-process available memory. Also, since the OS needs to handle a more varied set of events like e.g. a signal from the network card or the keyboard, the OS scheduler is more complex and needs more book-keeping. 
All this means that creating and managing OS-level threads is slower than managing Julia-level tasks.
Tasks which are managed by the language runtime's own scheduler, and which can be switched to and from without interacting with the operating system are also called _green threads_, and are also used in other languages such as Go.
"""

# ╔═╡ fc185cbe-37a2-45ba-bb5c-de3441722a70
md"""
### Cooperative multitasking and interrupts 
We've seen how one task is able to yield control to the scheduler (or another task).
A system of asynchronous programming that relies on tasks freely yielding control is called _cooperative multitasking_, as opposed to a system where the scheduler is able to stop other tasks, called _preemptive multitasking_.
For now, as of Julia 1.12, Julia's system of async is entirely cooperative: Tasks must yield explicitly or implicitly, to be stopped.

Unfortunately, it's pretty easy to write code that does not yield, including doing any implicit yielding such as allocating memory, but which nonetheless can run for a long time.
For example, the naive implementation of the fibonacci function:
"""

# ╔═╡ 87a0896d-38a8-4b44-84b9-8d35a284338d
fib(x) = x < 2 ? x : fib(x - 2) + fib(x - 1);

# ╔═╡ 5e644139-6db6-49a9-ab68-7ad8c872d483
# No allocations, no yielding. But if run with a larger number,
# it can take a long, long time.
@time fib(35)

# ╔═╡ 49629d75-2824-4938-999f-d02b65cc8c29
md"""
In the _best_ case scenario, scheduling a long-running task which doesn't yield will prevent other tasks from being run.
As we will see in a moment, non-yielding tasks can have even worse consequences.
As a programmer, the best policy is to never write tasks that don't occasionally yield.
"""

# ╔═╡ 5688d79a-0593-4722-b4f6-252b327746b2
md"""
### Tasks and the garbage collector
When the garbage collector (GC) runs, it mutates the data structure that keeps track
of heap allocations.
As the golden rule of async goes, _mutation requires exclusivity_.
That means no other task can allocate memory at the same time as the garbage collector runs.
Practically speaking, this means that when one tasks triggers the GC, the GC can't run until all other tasks has been blocked, lest they allocate and cause a data race in the GC.
For this reason, we say that Julia's GC is a _stop-the-world GC_.
In turn, that means that all running tasks need to know that the GC wants to run,
such that they can block.
How is this coordinated?

When the GC wants to run, it modifies a globally available pointer, such that it points to an invalid memory location.
The function `GC.safepoint()` loads data from this pointer. If the pointer is
invalid, this triggers a SIGSEGV (segfault signal), which is handled by Julia's custom SIGSEGV handler, to block the current thread until the GC has been run.
If the pointer is valid (i.e. the GC has not signalled it wants to run), this pointer load has no effect and takes only half a nanosecond.
Therefore, calls to the `GC.safepoint()` is peppered across various functions in the Julia runtime, like memory allocation or IO.

The inter-thread coordination needed to run the GC impacts how the user needs to write multithreaded code:

First, allocation-heavy code should be expected to scale worse with the number of threads than non-allocating tasks, because each thread creates garbage, so the GC needs to run more often.
And whenever it _does_ run, it needs to wait for every thread to reach the next safepoint.

Second, users need to be wary not to write code where _one_ task allocates memory, triggering the GC, when _another_ is running code that does not call `GC.safepoint()`, by allocating, doing IO, yielding to the schedular or doing dynamic dispatch.
If this happens, the first task will trigger the GC, blocking all tasks with safepoints, while the safepoint-less task will continue to run.
That means your multi-threaded workload will inadvertently turn single-threaded, potentially making it several times slower.

This issue occur most commonly when one task calls long running non-Julia code, like a C library, which naturally don't have safepoints for the Julia GC.
"""

# ╔═╡ 545e5844-1624-4f5d-b0bc-fa900cd8562c
md"""
### False sharing
A modern CPU will cache recently accessed memory in a faster CPU cache, in order to speed up future access to the same memory.
In modern, multi-core CPUs, some of the cache may be shared between cores, whereas other part of the cache is core-specific. Keeping the caches _coherent_, i.e. making sure that different parts of the cache, each with a CPU core that writes it, all agree on what is actually in memory at any given time is a massive coordination headache.
Let's all appreciate the hardware designers who have worked hard to solve this problem for us programmers - as long as we remember to use atomic operations, we can mostly ignore the problem of cache coherence.

_Mostly_. There is one case I know of where the problem of cache coherence rears its head and appears to us programmers, and that is _false sharing_.

When the CPU cache copies data, it copies whole _cache lines_, usually 64 consecutive bytes, depending on your specific CPU model.
The CPU's _cache coherence protocol_ keeps track of which cache lines has been altered by one core. If another core requests the same cache line, the line needs to be synchronized between cores.

This has implication for asynchronous code: If one task mutates a piece of data, then all other data allocated on the same cache line will be slower to access for tasks running on another core.
We call this _false sharing_, because even though no single piece of data is shared between tasks, different pieces of data allocated on the same cache line still needs to use the cache coherence protocol.
False sharing doesn't cause data races, but it can tank performance.

We can demonstrate it with the code below, which increments every element in an array using multiple tasks in parallel: When `false_share` is benchmarked the first time below, the eight tasks works on interleaved elements of the vector. Since a 64-byte cache line contains 64 single-byte elements, that means all eight tasks will write to the same cache lines at the same time.
In contrast, the second time the function is benchmarked, each task will get its own 64-byte slice of the vector to update such that no cache line is shared between tasks.
"""

# ╔═╡ 9a6d75a0-0f0c-4909-886d-9a2377ef0ee7
begin
	function update_bytes(v::Vector{UInt8}, start::Int, step::Int)
		chunksize = div(length(v), 8)
		for _ in 1:1_000_000
			p = start
			for _ in 1:chunksize
				v[p] += 0x01
				p += step
			end
		end
	end
	
	function false_share(starts, inc)
		v = zeros(UInt8, 512)
		tasks = map(1:8) do i
			@spawn update_bytes(v, starts[i], inc)
		end
		foreach(wait, tasks)
	end
end;

# ╔═╡ 05524538-352d-4dff-9f24-5844b46635c8
@btime false_share(1:8, 8)

# ╔═╡ af561fc4-9b1b-405a-90a6-8bc18e93bf3f
@btime false_share(1:64:512, 1)

# ╔═╡ 602d6b6d-24b2-4cd8-901d-f893772745fb
md"""
## Higher level synchronization abstracts
The abstractions provided by atomic operations are too low level for most programmer's taste.
Luckily, Julia provide a whole bunch of abstractions to make our asynchronous lives easier.

Most of these abstractions are in the form of datastructures that support async-friendly operations, which are guaranteed not to cause data races.
A datastructure or operation which is data race free is described as _threadsafe_, since it's safe to operate on it using multiple tasks, even if those tasks are running in parallel on different threads.

### Locks: The simple spinlock
A _lock_ is a data structure used to ensure only one task has access to a piece of data at a time.
They also have a more illustrative name: _Mutexes_, short for _mutual exclusion_.

When a task calls `lock` on a lock (also called _taking_ or _acquiring_ the lock), it is said to _hold the lock_.
If another task tries to take a lock that is already held, the task will be blocked.
Once the task holding the lock has called `unlock` on the lock, the waiting tasks will be unblocked, and the lock available for other tasks to take.

To illustrate locks, let's implement a poor man's version of a _spinlock_, the simplest type of lock.
"""

# ╔═╡ 354447dc-030a-4ced-a2cf-3fa89865933e
begin
	mutable struct SimpleSpinLock <: Base.AbstractLock
		@atomic held::Bool
		
		SimpleSpinLock() = new(false)
	end

	function Base.lock(lck::SimpleSpinLock)
		while (@atomicswap :acquire lck.held = true)
			yield()
		end
		return nothing
	end

	function Base.unlock(lck::SimpleSpinLock)
		if !(@atomicswap :release lck.held = false)
			throw(ConcurrencyViolationError("Unlocked an unlocked SpinLock"))
		end
	end
end;

# ╔═╡ 1c5c9cc7-de24-4784-9b0a-649a9a513d63
md"""
The defining property of a spinlock is that `lock` is implemented as a simple while loop.

Using this lock, we can now mutate some data asynchronously in multiple tasks at once, without worrying about violating the law of async.
Let's demonstrate this by pushing to a vector on two tasks in parallel.

Below, I'll use method `lock(::Function, ::AbstractLock)`, which is defined as:
```julia
function lock(f, l::AbstractLock)
    lock(l)
    try
        return f()
    finally
        unlock(l)
    end
end
```
This is generally preferred to use this function, in order to make sure the lock is never held indefinitely by a task that throws an error.

The general pattern to use locks - and by extension - the general pattern when mutating data shared between tasks, is:
```julia
lock(my_lock) do
	do_work(my_data_structure)
end
```

Alternatively, the equivalent `@lock` macro may be used as in:
```julia
@lock my_lock do_work(my_data_structure)
```

Or, here, concretely:
"""

# ╔═╡ 97220abd-8334-45ca-895f-2e9d76dd77cd
function puts_lots(lck::SimpleSpinLock, v::Vector{Int})
	for i in 1:100
		lock(lck) do
			push!(v, i)
		end
		# I only add this sleep to make sure one task doesn't
		# finish before another starts, to show our lock works
		sleep(0.001)
	end
end;

# ╔═╡ bf2a766b-1d44-485a-a837-f96d549d09fd
begin
	v = Int[]
	lck = SimpleSpinLock()
	t = @spawn puts_lots(lck, v)
	puts_lots(lck, v)
	fetch(t)
	v
end

# ╔═╡ ca20d8be-b038-46dc-bc37-898e2482ac09
md"""
Locks nicely abstract the underlying atomic operations, but they still have sharp edges.
Since tasks will wait for a lock indefinitely until it is released, it's easy to create a situation where a task is waiting for a lock to be released, but the unlocking of the lock is dependent on the task, which is stuck waiting.

For example, if you try to implement a recursive function that takes a spinlock, the first call will take the lock, and then the function will call itself, attempt to take the lock again, and get stuck.
When this happens, the program will never progress.
Such a situation is called a _deadlock_.

The vulnerability to deadlocks comes from the nature of locks themselves, being essentially while loops.
There is no principled way to avoid them, but a good rule of thumb is to always notice when a task is doing a blocking operation while holding a lock.
If the unblocking of the task can ever be dependent on the lock being unlocked, there is potential for deadlock.

As the simplest kind of while loop, spinlocks bring both advantages as disadvantages:
One one hand, the tight while loop means that spin locks have low latency - once the lock is unlocked, a waiting task will almost immediately be able to take it.
On the other hand, each waiting task is kept busy by the continual while loop. If there are many tasks waiting, or if the wait time can be expected to be long, this represents a lot of pointless work for the computer.

Mostly, people shouldn't use spinlocks. With the help of something called a _condition_, we can build a better type of lock.

### Conditions
A condition is used to signal between tasks that something is ready.
When a task waits for a condition, it becomes blocked, yielding to the scheduler.
Then, when a notification is sent to the condition, the waiting tasks are woken up and rescheduled. 

Compared to a spinlock, the main advantage of a condition is that a task waiting for a condition don't use the CPU.

In Julia, we can use `Threads.Condition` to create a condition, and use it with `wait(::Threads.Condition)` and `notify(::Threads.Condition)`.
Just like a lock is taken with the `lock` function, so must a condition be taken with `lock` to call `wait` or `notify`.
Note that a successful call to `wait` will automatically unlock the condition immediately _before_ the waiting task yields - if it didn't, conditions would be useless, since no-one would ever be able to lock and notify a condition that had a task waiting for it.

Let's re-implement one of the earlier examples, where I used an atomic as a condition, and waited for it in an inefficient while loop:
"""

# ╔═╡ 5cae8006-d72f-4771-8588-ae7bddc6ab6b
function mark_when_ready(is_ready::Threads.Condition, shared)
	sleep(0.2) # do some computation
	shared[] = 42
	@lock is_ready notify(is_ready)
end;

# ╔═╡ 3f80113b-669a-44d8-86d6-471c43154958
function return_when_ready(is_ready::Threads.Condition, shared)
	@lock is_ready wait(is_ready)
	shared[]
end;

# ╔═╡ 96d968b3-4662-4985-9a81-7fe6cdcbb524
let
	is_ready = Atomic{Bool}(false)
	shared = Ref(0)
	t = @spawn return_when_ready(is_ready, shared)
	sleep(0.1)
	mark_when_ready(is_ready, shared)
	wait(t)
	shared[]
end

# ╔═╡ b3b9c83b-167e-4de7-b824-ef2a754bc91b
let
	is_ready = Threads.Condition()
	shared = Ref(0)
	t = @spawn return_when_ready(is_ready, shared)
	sleep(0.1)
	mark_when_ready(is_ready, shared)
	wait(t)
	shared[]
end

# ╔═╡ b16fee73-48e2-4de3-8a51-bf6684e15e17
md"""
### ReentrantLock
Spinlocks provide low latency, but occupy the CPU and scheduler when they are waiting to be taken. On the contrary, conditions allow a task to wait without using the CPU.

In Julia, the `ReentrantLock` combines the strengths of both spinlocks and conditions: When a task tries to take a `ReentrantLock`, it first acts like a spinlock for a few iterations.
If the task has still not succeeded in taking the lock, it will block and wait to be notified when the lock is unlocked. Then, when it's woken up when the lock is unlocked, it reverts to is spinlock-like loop.
This hybrid approach makes `ReentrantLock` versatile and earn its place as the default lock type in Julia.
Spinlocks _are_ available as `Threads.SpinLock`, but should essentially never be used.

The name `ReentrantLock` comes from their _reentrancy_.
In this context, it means that the same task can take, and release the lock an arbitrary amount of times without deadlocking.
This makes reentrant locks usable in recursive algorithms.

### Lockable
Locks are mostly used to protect some other value from being accessed concurrently.
That requires the user to remember what data goes with which lock, which suggests the user interface could be improved somehow. Enter `Lockable`.

A `Lockable{T, L <: AbstractLock}` wraps a value of type `T` and a lock (which defaults to a `ReentrantLock`).
The value can be accessed with `Base.getindex`, as in `my_lockable[]`, but only when the lockable is locked.
In my opinion, this is a straight up improvement on the API of locks.

So, idiomatic use of a lock could look like below - barring of course the contrivedness of adding two numbers by taking a lock one million times.
"""

# ╔═╡ 0d5d8b7e-5045-4880-b9e3-d86e1ff3af2c
let
	lockable = Base.Lockable(Ref(0))
	tasks = map(1:10) do _
		@spawn begin
			for i in 1:100_000
				# Two Base.getindex, once for the lockable,
				# and once for the RefValue
				@lock lockable lockable[][] += 1
			end
		end
	end
	foreach(wait, tasks)
	@lock lockable lockable[][]
end		

# ╔═╡ fb968464-b790-4fe0-ba3b-2bd55c159f3f
md"""
### Semaphore
A semaphore is a lock that can be held N times at once, by different tasks if necessary.
Any task that tries to take a semaphore that is already held N times will block until one of the tasks that holds the semaphore releases it.
For some reason, a `Base.Semaphore` doesn't use the functions `lock` and `unlock`, but instead `Base.acquire` and `Base.release`.
Conceptually, locks can be seen as a special case of semaphore that has N = 1.

Semaphores are used more rarely than locks, because the main use case for locks is to ensure that only a single task has exclusive access to data, such that the data can be mutated.
_Mutation requires exclusivity_, as you know.

One situation where semaphores are useful is when you are launching external code from Julia tasks.
Say, for example, you want to run some single threaded shell command.
You might want to only run `Threads.nthreads()` commands at the same time, since there is no point to running more commands than the OS's scheduler can run on the available CPU cores.
The issue here is that the Julia scheduler is not aware that spawning a shell command takes up resources in the background, and so it will happily launch all the tasks at once.

In this case, you can do something like:
"""

# ╔═╡ 4aa430d1-3efc-4e88-ab58-4a5448815567
begin
	tasks = Task[]
	semaphore = Base.Semaphore(8)
	tasks = map('A':'X') do letter
		@spawn begin
			Base.acquire(semaphore) do
				sleep(rand())
				# A BufferStreams is a threadsafe version of IOBuffer
				io = Base.BufferStream()
				run(pipeline(`echo $(letter)`, io))
				close(io)
				String(strip(String(read(io))))
			end
		end
	end
	# Note that the order of the result depends on the order
	# of the tasks created by the `map`, and NOT the order in
	# which they completed. Therefore, the result is guaranteed
	# to be in alphabetical order.
	join(map(fetch, tasks))
end	

# ╔═╡ 97e2f87b-b7a8-4ab2-b55a-28bbb86309d9
md"""
### Channel
A channel is a simple collection of elements, a little like a `Vector`, which is threadsafe because all its operations are guarded by a lock.
Channels are intended to be used to pass values between tasks.

Even though they are conceptually similar to threadsafe vectors, they have slightly different semantics.
For one, channels have a capacity - the maximum number of elements it can store before it's full - which defaults to zero.
The functions used to mutate channels are also slightly different from vectors:

* `take!(::Channel)` will pop off the _first_ element of the channel (similar to `popfirst!`) if it is not empty.
  If the channel is empty, the task will block until an element is available.

* `put!(::Channel, x)` pushes `x` to the channel, if the channel isn't full. If it's full, the task will block until there is room in the channel.
  A zero-capacity channel will detect if there is both a task waiting to `take!` and `put!`, and will pass the value directly from one task to the other, unblocking them both. This is why the default zero-sized channels are still useful.

* A channel can be closed with `close`. Calling `put!` on a closed channel, or `take!` on a closed, empty channel will error.

* Iterating over a channel is equivalent to calling `take!` in a loop, until the channel is closed and empty (in which case `iterate` returns `nothing` instead of throwing an error).

A common use case of channels is where one or more tasks continually produce values, whereas others consume and process these values as they are coming in.
For sake of example, suppose we're writing a program that recursively processes files in a directory subtree. We have one task crawl through the filesystem and identify the files to process, and a set of worker tasks that process these files:
"""

# ╔═╡ 3a30d8db-6730-4f5b-98fd-7aca5bbe8dc8
begin
	function produce(top_dir, channel::Channel{String})
		for (directory, _, files) in walkdir(top_dir), file in files
			if last(splitext(file)) == ".jl"
				put!(channel, joinpath(directory, file))
			end
		end
		close(channel)
	end

	function consume(channel)
		for path in channel
			sleep(0.5)
			println("Found $(path)!")
		end
	end

	function main(top_dir, n_threads)
		channel = Channel{String}(2048)
		producer = @spawn produce(top_dir, channel)
		workers = map(1:n_threads) do _
			@spawn consume(channel)
		end
		wait(producer)
		foreach(wait, workers)
	end
end;

# ╔═╡ b20ed863-cdf8-447b-923b-23339ba0e8cc
main(".", 4)

# ╔═╡ c8194ce4-f730-48ec-aaf7-9e2f3f9dcef7
md"""
## Useful high-level patterns
### Macro `@threads`
Most of my own use of async is pretty straightforward: I want to compute N things independently, and I want it to go faster by running them in parallel.
That's when the macro `Threads.@threads` comes in handy. When placed in front of a for-loop, it spawns `Threads.nthreads()` tasks, and partitions the iterations among the tasks.

Here's an example of how to use `@threads`
"""

# ╔═╡ a426d78d-f964-4d19-b5fa-7ef0c0d54341
let
	inputs = Set(1:16)
	results = Vector{Int}(undef, length(inputs))
	@threads for (i, input) in collect(enumerate(inputs))
		sleep(rand() / 2) # do some computation
		results[i] = input + 1 # store the results
	end
	results
end

# ╔═╡ cc343ccf-4648-4121-95ff-29b81bd9cf9b
md"""
A few notes on the code above:

The macro takes an optional scheduling keyword, that determines how each iteration is split among the tasks. The "scheduler" here just refers to how `@threads` work, and is distinct from the scheduler in Julia's runtime. By default, the scheduler keyword argument is `:dynamic`. This dynamic scheduling will partition the iterations roughly equally among the tasks.
That's the reason I call `collect` on the enumeration - in order to be able to compute even partitions of the iterable, it needs an indexable collection.
Another downside is that some of the tasks may, by random chance, get a slice of the input elements that happen to take a shorter time to process. When that happens, your computer's potential for parallelism is not fully exploited, as some of the tasks will finish early and be idle.

Alternatively, you can use `:greedy` scheduling. Here, a number of worker tasks are spawned, each of which will simply take the next available iteration. Under the hood, this in implemented similar to the `Channel` example above.
Having each element go through channels incurs some overhead per element, but on the positive side, every worker task is kept maximally busy - and there is no need to `collect` an iterable, since the greedy scheduler doesn't need an indexable iterable.

In some older texts on Julia parallelism, the author will recommend instead an **incorrect** pattern that relies on `threadid()` like this:

```julia
# Do NOT use this pattern!
results = Vector{Int}(undef, Threads.nthreads())
@threads for input in inputs
	results[Threads.threadid()] = input + 1
end
```

**This is buggy**, because the Julia scheduler may move tasks between threads at will, so there is no guarantee that the tasks will execute every loop iteration on different threads.

#### OhMyThreads.jl
The `@threads` macro is a little crude and often suboptimal. For example, it's not very advanced in how it partitions the input among the tasks, and there is no way to customise the number of tasks it spawns.

For more customizability, see the package OhMyThreads.jl, which provides the similar, but more optimised and versatile `@tasks` macro.
"""

# ╔═╡ dbb7b9f6-da94-4bac-b172-c7a4bb31d5c4
md"""
### Macro `@sync`
A common pattern in async code is that a function spawns a bunch of tasks to work in parallel, and then at some point, the function needs to make sure all the tasks are done before proceeding.
In some of examples above, I've achieved this by creating a vector of tasks, then called `foreach(wait, tasks)`.

What then, if one of the tasks throws an exception? Calling `wait` on a failed task will throw a `TaskFailedException`. Surely, this could be handled better.

The `@sync` macro provides a convenient way to wait for multiple tasks, while also handling the case when one or more of them throws.
The way it works is that any `@spawn` statement inside a block marked as `@sync` will be collected, and when the sync block ends, each task will be waited for. All the exceptions thrown by tasks will be collected into a `CompositeException` that will be thrown at the end of a sync block.
For example:
"""

# ╔═╡ 59f4a2be-acc3-4aed-b1ef-e5d0dec70f51
# No errors are thrown
@sync begin
	@spawn (sleep(0.5); println(2))
	@spawn println(1)
end;

# ╔═╡ a3c5932a-8ff9-4294-9130-9c661ed8dee6
# Here, it throws an error
try
	@sync begin
		@spawn (println(1))
		@spawn (sleep(0.3); throw(ArgumentError("Some error!")))
	end
catch err
	if err isa CompositeException
		# If we want to inspect the error later, we can assign it
		# to a global like so
		global comp_error = err
		println("One or more of the tasks failed with the following errors!")
		@show err.exceptions
	else
		rethrow() # this should never happen
	end
end

# ╔═╡ 5729484b-0467-403e-88f9-28677f03649d
md"""
Be aware that `@sync` is a macro, and therefore only operates on the _source code_ of the content of the sync block.
That means it's only able to detect _literal_ `@spawn` blocks.
If you e.g. write a function that spawns a task, and then call this function in the sync block, the macro will not be aware that a task was spawned and therefore will not do anything to synchronize that task.
"""

# ╔═╡ 513c6b05-23ed-4174-802a-2ade2acf2adc
md"""
### The spawn-fetch pattern
Another common pattern when you have a function that does two or more things which can run independently.
For example, suppose you have a function that needs to read in both a config file and a data file, and then process the data according to the configuration.
The processing depends on having read the two files, but the two files can be read in parallel.

Here, I would use what I call the spawn-fetch pattern, where one or more tasks are spawned, and then almost immediately fetched.
This is what it looks like:
"""

# ╔═╡ cc56cdff-9d19-46c1-934c-f436439a2980
function process_by_configuration(data_path, config_path)
	task = @spawn open(read_data, data_path)
	open(read_config, config_path)
	process(data, fetch(task)::Configuration)
end;

# ╔═╡ 5c1ac369-15ee-4b36-a7bc-5ff1ba8cd8b1
md"""
Above, the configuration file is being read while another task is reading the data file in the background, allowing the two to work in parallel. Then, the result of the task is fetched before proceeding. Remember that Julia currently doesn't do type inference across tasks, so I need to typeassert the return type of `fetch`.

This pattern is only useful for relatively high level functions, because of the five microsecond overhead associated with spawning and managing a task.
Thus, if this pattern is used in low-level code, the benefit from parallelism will be outweighed by the task management overhead.
"""

# ╔═╡ a6172e40-8288-440f-b684-2268b218c3f3
md"""
## Avoid reasoning about threads in Julia
Throughout this notebook, I have spoken of asynchronous code in terms of code running in multiple _tasks_, whereas other material on this topic usually centers on running multiple _threads_.
For example, the most basic examples of parallelism in Rust code will explicitly spawn and manage OS-level threads.

In one sense, the distinction is straightforward, since there is a clear denotational difference: A _task_ is a piece of code that can be executed by the scheduler. A _thread_ is a resource provided by the operating system, upon which one task can be run at a time.

However, systems differ in which of these two concepts are considered _central_, tasks or threads.
As Julia's support for asynchronous code has improved, it has become increasingly apparent that tasks, and not threads, provide the most useful level of abstraction to work on, and that users should avoid reasoning about threads where practical.
Instead, threads should be seen as a resource transparently provided by the operating system, similar to RAM or CPU cache.

To continue the analogy between the garbage collector and scheduler, it is possible to reason about Julia data structures in terms of pointers to the memory addresses where the data is located.
But this is a poor level of abstraction: Referring to objects by their memory location is both cumbersome, and also prevents important optimisations like stack-allocating memory transparently, and moving data in memory.
Similarly, writing asynchronous code with threads in mind cause at least two issues that I know about:

First, the author of a library can't know how many threads are available on the computer where the code is running, nor which other libraries are running asynchronous code concurrently.
Therefore, the number of available and busy threads must be assumed to always be in flux.

Second, the Julia scheduler may pause a task, then resume it on another thread. The fact that the current thread may change any time makes the concept of a 'current thread' ephemeral and meaningless.
"""

# ╔═╡ a305ee04-498a-4933-a813-8550f50a761d
md"""
## The future of async in Julia
Async has been an area of intense development in Julia since shortly after version
1.0. It was deemed a priority to flesh out async quickly after 1.0, because it was
feared that in the absence of a good set of abstractions for async, the Julia ecosystem might begin to rely too much on synchrony, making async harder to add later.
Even though the most important work on async has already been done, there are still
a few areas that the core developers seek to improve:

### Inference in tasks
Currently, Julia can't do inference across tasks. That implies that e.g. `fetch`
is always inferred as `Any`.
Practically speaking, I recommend users to typeassert the results of `fetch`.
This is obviously annoying, and it'd be much nicer
if Julia had inter-task inference on the same level as inter-function inference.

### Better multithreaded garbage collection
As previously mentioned, having a stop-the-world garbage collector currently creates problems
with concurrent workloads.
There are several ways the situation could be improved in the future:

* An entirely new garbage collector design, which requires less synchronization
  between individual threads, such as the recently added
  [non-moving immix GC](https://github.com/JuliaLang/julia/pull/56288)
  could reduce the need for stopping the world.

* The Julia compiler could gain an understanding of when a function allocates.
  A function that doesn't allocate, or only allocates in a foreign function call,
  does not need to be stopped for the GC to run.

### Task preemption
Async in Julia is currently completely cooperative, meaning that the system relies on tasks voluntarily and frequently yielding to the scheduler.
That requirement sets traps for casual users of async, who can too easily forget to check if their tasks actually do yield often enough. Tears ensue.

Although there, to my knowledge, hasn't been any concrete initiatives, it's possible that Julia may introduce some limited preemption in the future, such that the scheduler may actively interrupt running tasks.
The trick is how to devise a system where tasks may be interrupted while they are doing arbitrary computation, without interrupting them in the middle of some critical operation, thereby causing stack corruption or other awfulness.

### Allow IO to run from other threads than thread 1
Some scheduler operations, such as IO and `Timer` callbacks, can currently only run on thread 1.
This limitation awkwardly breaks the abstraction that all tasks may run on any thread, such that the user does not need to think about scheduling.

For example, if the user writes a single task which does not yield, and the scheduler woefully schedules that on thread 1, then no IO can run at all until that task yields again.
If the unyielding task relies on an IO operation in order to complete, the system will deadlock.

Practically speaking, this situation can be avoided by following the maxim to _never write an unyielding task_, but it's still unfortunate that the consequences of failing to do so are unnecessarily dire.

### Various optimisation
Many of the important moving parts has not been thoroughly optimised.
In particular, the core devs have long talked about making the `Task` objects
faster and more memory efficient to create.
That would enable lower level parallelism, such as using the spawn-fetch pattern more broadly.

There is also slow, but ongoing work on optimising the scheduler itself, as well as types like `ReentrantLock` and `Channel`.
"""

# ╔═╡ 4a918040-1d9d-4c7d-967f-be5e3d91652f
md"""
## Further reading
I recommend the following texts, which have served as inspiration for this blog post

* [Rust Atomic and Locks by Mara Bos](https://marabos.nl/atomics/)
* [What every systems programmer should know about concurrency by Matt Kline](https://assets.bitbashing.io/papers/concurrency-primer.pdf)
* [Asynchronous Programming in Rust by Carl Fredrik Samson](https://www.packtpub.com/en-dk/product/asynchronous-programming-in-rust-9781805128137)
* [The Little Book Of Semaphores by Allen B. Downey](https://greenteapress.com/wp/semaphores/)
"""

# ╔═╡ 00000000-0000-0000-0000-000000000001
PLUTO_PROJECT_TOML_CONTENTS = """
[deps]
BenchmarkTools = "6e4b80f9-dd63-53aa-95a3-0cdb28fa8baf"
PlutoUI = "7f904dfe-b85e-4ff6-b463-dae2292396a8"

[compat]
BenchmarkTools = "~1.6.0"
PlutoUI = "~0.7.60"
"""

# ╔═╡ 00000000-0000-0000-0000-000000000002
PLUTO_MANIFEST_TOML_CONTENTS = """
# This file is machine-generated - editing it directly is not advised

julia_version = "1.11.3"
manifest_format = "2.0"
project_hash = "81693cf1c32947d8a969f76f9fb759d6f2b3c002"

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

[[deps.BenchmarkTools]]
deps = ["Compat", "JSON", "Logging", "Printf", "Profile", "Statistics", "UUIDs"]
git-tree-sha1 = "e38fbc49a620f5d0b660d7f543db1009fe0f8336"
uuid = "6e4b80f9-dd63-53aa-95a3-0cdb28fa8baf"
version = "1.6.0"

[[deps.ColorTypes]]
deps = ["FixedPointNumbers", "Random"]
git-tree-sha1 = "b10d0b65641d57b8b4d5e234446582de5047050d"
uuid = "3da002f7-5984-5a60-b8a6-cbb66c0b333f"
version = "0.11.5"

[[deps.Compat]]
deps = ["TOML", "UUIDs"]
git-tree-sha1 = "8ae8d32e09f0dcf42a36b90d4e17f5dd2e4c4215"
uuid = "34da2185-b29b-5c13-b0c7-acf172513d20"
version = "4.16.0"
weakdeps = ["Dates", "LinearAlgebra"]

    [deps.Compat.extensions]
    CompatLinearAlgebraExt = "LinearAlgebra"

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

[[deps.Profile]]
uuid = "9abbd945-dff8-562f-b5e8-e1ebf5ef1b79"
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
# ╟─8b83e436-dc12-11ef-1b27-1d3fdefb24c1
# ╠═21b2cbda-17d6-4466-adbc-5e513482e1af
# ╠═0746182a-2e0e-4bc3-a8e5-459b8a7a6f28
# ╠═b278c476-74e9-4399-a05c-7c15111bfd3c
# ╟─17ddbb08-cd8d-446e-b806-dc3000dc2184
# ╠═8f6cf27f-5648-40ab-b029-d52c0eaf3883
# ╠═2bd97906-edc8-48e8-ac2d-6a87a2e01fe5
# ╟─c4f33908-efab-4654-b9dd-b4e46573428a
# ╠═5e45c378-3788-484c-906b-86586c8cd7c8
# ╠═a8acd763-7068-4a2c-9dd9-8f926680f8b7
# ╠═de1f77c2-bdbb-4192-ba24-da41489c0a8b
# ╟─f74b1284-dece-4216-bb06-29514415ff5f
# ╟─ef36118e-2fdf-4c99-a9da-f8cbc6885fb3
# ╠═67664ef0-0f00-4388-a47c-9d97d7b443a5
# ╟─0f800d3f-34ae-4f6c-b6bc-d7c82c1c1af2
# ╟─20ee5cfa-b80c-4a2f-8314-67048c1c429b
# ╟─a279c000-2154-44b9-bb72-41862b61fcbc
# ╠═0668560d-d2ff-49ae-a5ae-3a92ba269e53
# ╠═a40cd157-fde1-49be-9156-0b8caa12e5a5
# ╟─fc99d8b6-9b32-46a4-bde0-9108b029e43e
# ╠═602c3a65-79c2-4e6b-a70d-c9b3c1df20ca
# ╟─592fc034-8344-4cb7-b378-6ced7205ad9e
# ╠═a5fa1503-5880-4d0e-aba8-0c3ee34b6dfa
# ╟─422c8758-e0f6-491e-ad0d-743f4d9e7c48
# ╠═107291d1-1c00-45a7-9225-be541ff44ab6
# ╠═4266d974-0dca-4798-9952-2a7e8c77968c
# ╠═6a1c5924-92b6-40ef-967f-494332ade500
# ╟─718eac91-b4d1-4dee-ac67-76e4cb8ef341
# ╠═fde5713b-2774-43dc-90d1-36b1446d4540
# ╟─19609694-3c8e-4b46-be18-63011e315308
# ╠═9fe22bc2-2c4a-423d-85cb-60a16ad68ea3
# ╠═00e9e859-3238-41f8-93ca-b2243495083b
# ╟─b74ae921-f376-4a40-b042-4e7a777902ef
# ╠═65fc3a2d-de89-4cc2-8f1e-dbc2f90c416d
# ╠═a08bd0d6-776e-46a7-a186-614cc0bbd65d
# ╟─fd87476d-b32b-4785-9fdc-21da66b9adaa
# ╟─27133bd1-433e-4bc4-ac6e-c06b9c245b6e
# ╠═e07e174d-3719-4025-91aa-f56365a68453
# ╠═d11037b5-241d-4878-9602-0043bb21e72b
# ╠═96d968b3-4662-4985-9a81-7fe6cdcbb524
# ╟─2a383feb-22d8-48d8-b247-c20ec5bbe91b
# ╟─606f9ce3-90f2-442c-aac7-d2a24a61f180
# ╠═69652455-0e9f-4b2a-bbef-464841dc9bc5
# ╠═175bc3f1-1a25-4d0a-b454-44b34b5efe11
# ╟─f2f2e703-9874-4872-958b-d653f9a8365a
# ╟─9d335a94-9b57-4624-a0f0-b54829a951e5
# ╟─fc8d9128-9788-416f-b387-575c87e73360
# ╠═62b369f9-15f7-4737-8dda-40211f8f22c0
# ╟─c82ec1aa-dd68-42e1-9ff0-1e1222c916f3
# ╟─69b86287-ad33-486a-9b70-b4eacb443f43
# ╟─1d70bc25-b941-4481-8579-80b70e7b6846
# ╟─6b900c42-127e-463f-b941-c321297537f3
# ╟─725773df-24c7-4547-84fc-3cd163d19136
# ╟─766372a3-fb2c-4e86-8916-37bcaf9c0d79
# ╟─fc185cbe-37a2-45ba-bb5c-de3441722a70
# ╠═87a0896d-38a8-4b44-84b9-8d35a284338d
# ╠═5e644139-6db6-49a9-ab68-7ad8c872d483
# ╟─49629d75-2824-4938-999f-d02b65cc8c29
# ╟─5688d79a-0593-4722-b4f6-252b327746b2
# ╠═545e5844-1624-4f5d-b0bc-fa900cd8562c
# ╠═9a6d75a0-0f0c-4909-886d-9a2377ef0ee7
# ╠═05524538-352d-4dff-9f24-5844b46635c8
# ╠═af561fc4-9b1b-405a-90a6-8bc18e93bf3f
# ╟─602d6b6d-24b2-4cd8-901d-f893772745fb
# ╠═354447dc-030a-4ced-a2cf-3fa89865933e
# ╟─1c5c9cc7-de24-4784-9b0a-649a9a513d63
# ╠═97220abd-8334-45ca-895f-2e9d76dd77cd
# ╠═bf2a766b-1d44-485a-a837-f96d549d09fd
# ╟─ca20d8be-b038-46dc-bc37-898e2482ac09
# ╠═5cae8006-d72f-4771-8588-ae7bddc6ab6b
# ╠═3f80113b-669a-44d8-86d6-471c43154958
# ╠═b3b9c83b-167e-4de7-b824-ef2a754bc91b
# ╟─b16fee73-48e2-4de3-8a51-bf6684e15e17
# ╠═0d5d8b7e-5045-4880-b9e3-d86e1ff3af2c
# ╟─fb968464-b790-4fe0-ba3b-2bd55c159f3f
# ╠═4aa430d1-3efc-4e88-ab58-4a5448815567
# ╟─97e2f87b-b7a8-4ab2-b55a-28bbb86309d9
# ╠═3a30d8db-6730-4f5b-98fd-7aca5bbe8dc8
# ╠═b20ed863-cdf8-447b-923b-23339ba0e8cc
# ╟─c8194ce4-f730-48ec-aaf7-9e2f3f9dcef7
# ╠═a426d78d-f964-4d19-b5fa-7ef0c0d54341
# ╟─cc343ccf-4648-4121-95ff-29b81bd9cf9b
# ╟─dbb7b9f6-da94-4bac-b172-c7a4bb31d5c4
# ╠═59f4a2be-acc3-4aed-b1ef-e5d0dec70f51
# ╠═a3c5932a-8ff9-4294-9130-9c661ed8dee6
# ╟─5729484b-0467-403e-88f9-28677f03649d
# ╟─513c6b05-23ed-4174-802a-2ade2acf2adc
# ╠═cc56cdff-9d19-46c1-934c-f436439a2980
# ╟─5c1ac369-15ee-4b36-a7bc-5ff1ba8cd8b1
# ╟─a6172e40-8288-440f-b684-2268b218c3f3
# ╟─a305ee04-498a-4933-a813-8550f50a761d
# ╟─4a918040-1d9d-4c7d-967f-be5e3d91652f
# ╟─00000000-0000-0000-0000-000000000001
# ╟─00000000-0000-0000-0000-000000000002
