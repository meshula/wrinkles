<!-- To add to the keynote -->

# What OTIO Does Today

(image of timeline)

Otio can effectively encode a timeline and its metadata.  We can reconstruct these boxes and their places on tracks and such in multiple applications, and even attach lots of different kinds of data to it.

## Temporal Coordinate Systems

However, if we look at that structure with our graphics brain on, we can see that intuitively there is a hierarchy of coordinate systems visible.

- The Top timeline has a coordinate system (that the playhead travels when the composition is being played back)
- Each track has a coordinate system that the clips sit in
- .\.\.and each clip has a coordinate system that media lives in

The opeartions we want to do on this coordinate system hierarchy have at least two basic operations:

1. Projection
2. Sampling

### Projection

Projection is the act of taking a value from one coordinate space to another.  This could be a single coordinate, as in the case where we have a playhead with a coordinate in the global flattened space and want to know the corresponding time in the media space,or 

#### Points



#### Ranges

### Sampling
