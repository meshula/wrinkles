# Notes On Flattening

(from slack)
I thought of a (to me) not obvious but really useful algorithm that is kind of
a dual to the flattening algorithm you wrote.  I think it uses most of the same
pieces but produces a different data structure.  If you think about what your
algorithm does, it transforms the timeline into a single track of video from
many.  But the OTHER probably very useful data structure, because you can make
queries on it that are really useful, is to take a timeline and unroll the
nesting such that you get a single track made up of stacks, where each stack
contains all the media that is concurrent for the interval of the stack.

Imagine a timeline with two tracks:

```
[  a   |  b  |   c   ]
[ d |      e     | f ]
```
```
from:
[  a   |  b  |   c   ]
[ d |      e     | f ]
[s1 |s2|  s3 | s4| s5]
```
This algorithm would produce: ^
(I put them next to each other so you could see them together)

where:
s1: stack{a',d}
s2: stack{a'',e'}
s3: stack{b,e''}
s4: stack{c',e''}
s5: stack{c'',f}

Walking across this resulting track would give you all the concurrent media /
time slice.  It occured to me while thinking of ways to accelerate a
calculation that Nick and I are working on.

## Additional Notes

I think we could use this to accelerate a lot of computations.

There is a dual of THIS structure that adds a pointer from each media reference
back to the stacks in which it lands that answers a lot of projection
questions.

*@QUESTION:* Can we do this analytically without rasterizing the timeline?  Is
             there another way to project the _bounds_ of something (rather than
             its entire internal topology) up through the timeline?

*@QUESTION:* One idea from Rick is that for the "upward" projection, the 
             direction in which we can't guarantee invertability, we could have
             a projection return a topology, or set of intervals or something
             -- but I'm not sure how to do this.  It seems intuitively possible?
             We should discuss w/ Rick further, I think.  It also turns out that 
             he designed the "manifold" system in the shader workflow so he has 
             really good context for what we're trying to do with this.
