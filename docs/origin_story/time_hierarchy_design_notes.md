# Open Questions

- Queries: do they need a domain/role argument?  Can they be done across all
  roles but always require a domain?
- Clip has a `source_range` at present, which is in the media space.  If there
  are multiple media spaces, should this be in the intrinsic space of the clip
  instead?
- Also, clip currently automatically uses the available range if source_range
  is not set.  With multiple source ranges, does clip lose that functionality
  as well, and must be fully specified?

- Roles/Domains: raw strings or tokens (in the style of `TfToken`)?
- Roles/Domains: should there be a `main` or `default` role or variant such
  that there is a simple choice if you only want to show one of the variants
- Should LOD/Proxy be one of the fields?
    - "left.4k" / "left.2k" / "left.240p"

- Current thought on the above: domain is a Token and Role is a list of tokens,
  stored per Media Reference.  A clip has a list of media references, and
  potentially a dictionary mapping roles/domains to individual media references
- tokens can be potentially lofted up to a higher scope

- do clips require a bounds?

# 8/17/2021

prior design:
- clips can have multiple media referneces, stored in a flat array
- media references have a single domain token and a list of role tokens

open questions:
- whether effects should be sorted/separated by domain or muxed together

for now:
- [x] going to promote the design out of the test scope and true the rest of the
    test implementation up to that design
- [ ] try and build some simple examples (like the audio_frames_to_render function)
- ...and then come back to the effects question once we have basic things working
- moved old tests into a deprecated_otio.zig file to separate it from the source
- does a time interval without a domain make sense?
- implement duration_for_domain

# Overview

Just a scratch sheet of notes observed from trying to implement the time
hierarchies in OTIO.

# Design Intent

OpenTimelinIO hierarchies, when converted into a third party application,
produces an isomorphic representation for the temporal and media information,
but _not_ the user interface.

The tracks, clips and transitions may _look_ different when viewed in different
applications, but the media content should render, barring specifically
out-of-domain unavailable operators (like specific video effects).

# Media Domains

One of the questions that comes up quickly is where to specify the _kind_ of
media that a clip is associated with.  This is necessary in order to ask a
question like "which audio samples are playing at a given time" or "which image
sources are active on a given frame and need to be composited".

We want to introduce the idea of 'media domains' as a formal part of
OpenTimelinIO.  This is needed to know how sampling functions interact with the
objects in OpenTimelinIO.  Furthermore, operators can be specific to a domain
(like a video effect) and can be ignored when traversing.

We want to establish an algebraic backbone for OpenTimelinIO and without
domains evaluating the graph becomes ad-hoc.

## Clips have multiple, domain specific media references

In this design, instead of having one media reference, clips grow a dictionary
of media references, where the key to the dictionary is the domain and the
value is the reference.

Systems that present data this way:

- FCPX (clips can be manually split into separate audio/video clips)
- edl (implicitly)

preferred by: 
    players

Pros:
- simpler data structure for OTIO (doesn't require any new types or referencing systems in OTIO), elegant backwards compatability (existing media references get promoted into having two references to the same file, one for audio and one for video)
- still allows splitting audio and video onto separate tracks, but doesn't provide tools for linking them
- tracks can still advertise a "filter" that limits what domains are "visible" for contents on them, while preserving multi domain media references

Cons:
- doesn't _look_ like the way the user interfaces in "professional" editing applications present this concept
- Domain-specific traversal requires walking all the way to the leaf media references in many cases, and requires transforming clips with out-of-domain media into gaps

## Tracks have a 'kind' which dictates the domain of any clips found in that track

In this model, if there is picture data and audio data that is to be associated
with each other, there is an additional bit of metadata that references one
from the other.  In avid, for example, these are referred to as "linked clips".
In the user interface, moving one slides the corresponding audio chunk on the
audio track around as well.

Systems that work this way:

- Avid
- FCP7
- Premiere
- OTIO*

*: OTIO has a field called "kind" on track, but it is not enforced by anything and purely a hint (at present).

Pros:
- resembles the user interfaces in professional editing applications
- finding all 

## Domains do _not_ participate directly in the transformation hierarchy

- If a clip has multiple media references with different domains, and a transformation is applied to the clip, it applies identically to all media references, regardless of domain
- If a user wants to apply a domain-specific temporal coordinate transformation, the clip must be broken up or duplicated up into multiple clips.
- Timeline, Stack, Track, Clip, and Media Reference all represent coordinate system references.

## Options for how to implement coordinate systems for effects on an `Item`

1. **unspecified**: We don't specify which coordinate space parameters are in for effects.
2. **same space**: All parameters are in the same (specified) space.
   We could say that all parameters to objects are expressed in the same space
   (the output or intrinsic space).  This solution is simple, but could be
   complicated for users to predict what a value does or what the context is
   for a value.
3. **grouped by domain**: We could split effects up into separate lists that
   target the various domains.  Within a domain's effects, all parameters are
   in the same (parent) space
3. **grouped by domain+stacked**: separate the effects by domain, but maintain
   a stack within a domain.
4. **Stack**: we allow effects to be interleaved and manage a stack of
   transforms as we move through the stack.  Effects are always in the local
   space at the top of the stack.
5. **Graph**: We express effects as an explicit graph.

The original design was #4 but realistically we are currently #1.

# Relevant Problems

Correlating lines of dialogue to shots.

For each picture shot in the output timeline, find all the associated sound
effect tracks for that shot.  For each sound effect shot that is a line of
recorded dialogue, log the line of dialogue and speaking character for the shot.
    - animation department
    - layout department
    - diversity reports
