

The operations defined earlier, such as trimming, offsetting, and so on, can be considered universal and applicable to all editorial domains. They are insufficient though, iIn order to fully develop an intermediate representation to allow interchange between editorial systems, a more full vocabulary of editorial operations must be laid out. The full set of operations is domain specific and beyond the scope of this paper, however we refer the reader to the open source OpenTimelineIO project (4), where the principles described here have been applied in the implementation of a system that does exercise a full set of editorial operations.

There is a whole world of optimization on such intermediate representations from compiler optimizations and syntax tree manipulations that are equally applicable to editorial systems. Using the editorial intermediate representation, trees can be transformed to optimize factors of interest, such as minimizing blending operations, minimizing retiming operations, and so on. Common operational subtrees can be identified and factored out so that intermediate  results of computation can be reused multiple times. Certain stages can be elided, for example, any operation with a color grade can be considered a stopping point for evaluation, and a signal raised for additional processing.


Much in the same way that this enables cross-processor compilation and optimization for computer programs, this allows for an interchange of data between editorial systems.

This also allows rendering engines to optimize aspects of the syntax tree during rendering, such as concatenation of affine transformations or ignoring out-of-domain operations.



Using the algebra, we can define a node graph structure for encoding the temporal description of composed media. The algebra can be used to form an intermediate representation for the editing operation which transforms the input media into the output timeline.

While an editor will view a timeline as a working document in its own right, what the timeline actually encodes is a set of instructions to a rendering engine or engines which uses the input media to synthesize the output playback timeline.  In this way, the timeline can be viewed as analogous to source code and the renderers can be viewed as analogous to compilers.  

Using this framework, and the algebra we previously present, we can construct a set of nodes for building an intermediate representation which can encode editorial operations represented by a timeline.  

An EDL is translated to our intermediate representation, then a renderer can access it to generate output samples. A translation system can take an EDL into our intermediate representation, and then output it without loss into another EDL format. 


