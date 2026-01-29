const std = @import("std");

const flatbuffers = @import("flatbuffers");

const @"#schema": flatbuffers.types.Schema = @import("tlb.zon");

pub const tlb = struct {
pub const @"BoundsType" = enum(i8) {
    pub const @"#kind" = flatbuffers.Kind.Enum;
    pub const @"#root" = &@"#schema";
    pub const @"#type" = &@"#schema".enums[0];

    @"Continuous" = 0,
    @"Discrete" = 1,
};

pub const @"CollectionItemType" = enum(i8) {
    pub const @"#kind" = flatbuffers.Kind.Enum;
    pub const @"#root" = &@"#schema";
    pub const @"#type" = &@"#schema".enums[1];

    @"TimelineItem" = 0,
    @"TrackItem" = 1,
    @"StackItem" = 2,
    @"ClipItem" = 3,
    @"GapItem" = 4,
    @"WarpItem" = 5,
    @"TransitionItem" = 6,
};

pub const @"ComposableType" = enum(i8) {
    pub const @"#kind" = flatbuffers.Kind.Enum;
    pub const @"#root" = &@"#schema";
    pub const @"#type" = &@"#schema".enums[2];

    @"Clip" = 0,
    @"Gap" = 1,
    @"Track" = 2,
    @"Stack" = 3,
    @"Warp" = 4,
    @"Transition" = 5,
};

pub const @"DomainType" = enum(i8) {
    pub const @"#kind" = flatbuffers.Kind.Enum;
    pub const @"#root" = &@"#schema";
    pub const @"#type" = &@"#schema".enums[3];

    @"Time" = 0,
    @"Picture" = 1,
    @"Audio" = 2,
    @"Metadata" = 3,
    @"Other" = 4,
};

pub const @"MappingType" = enum(i8) {
    pub const @"#kind" = flatbuffers.Kind.Enum;
    pub const @"#root" = &@"#schema";
    pub const @"#type" = &@"#schema".enums[4];

    @"Affine" = 0,
    @"Linear" = 1,
    @"Empty" = 2,
};

pub const @"MediaInterpolationType" = enum(i8) {
    pub const @"#kind" = flatbuffers.Kind.Enum;
    pub const @"#root" = &@"#schema";
    pub const @"#type" = &@"#schema".enums[5];

    @"Interpolate" = 0,
    @"Snap" = 1,
    @"DefaultFromDomain" = 2,
};

pub const @"MetadataType" = enum(i8) {
    pub const @"#kind" = flatbuffers.Kind.Enum;
    pub const @"#root" = &@"#schema";
    pub const @"#type" = &@"#schema".enums[6];

    @"Null" = 0,
    @"Bool" = 1,
    @"Int" = 2,
    @"Float" = 3,
    @"String" = 4,
    @"Array" = 5,
    @"KV" = 6,
};

pub const @"AffineTransform1D" = struct {
    pub const @"#kind" = flatbuffers.Kind.Struct;
    pub const @"#root" = &@"#schema";
    pub const @"#type" = &@"#schema".structs[0];
    @"offset": f64,
    @"scale": f64,
};

pub const @"ContinuousBounds" = struct {
    pub const @"#kind" = flatbuffers.Kind.Struct;
    pub const @"#root" = &@"#schema";
    pub const @"#type" = &@"#schema".structs[1];
    @"end": f64,
    @"start": f64,
};

pub const @"ControlPoint" = struct {
    pub const @"#kind" = flatbuffers.Kind.Struct;
    pub const @"#root" = &@"#schema";
    pub const @"#type" = &@"#schema".structs[2];
    @"in_val": f64,
    @"out_val": f64,
};

pub const @"DiscreteBounds" = struct {
    pub const @"#kind" = flatbuffers.Kind.Struct;
    pub const @"#root" = &@"#schema";
    pub const @"#type" = &@"#schema".structs[3];
    @"end": i64,
    @"start": i64,
};

pub const @"PackedScalar" = struct {
    pub const @"#kind" = flatbuffers.Kind.Struct;
    pub const @"#root" = &@"#schema";
    pub const @"#type" = &@"#schema".structs[4];
    @"bool_val": bool,
    @"float_val": f64,
    @"int_val": i64,
};

pub const @"MediaDataReference" = union(enum(u8)) {
    pub const @"#kind" = flatbuffers.Kind.Union;
    pub const @"#root" = &@"#schema";
    pub const @"#type" = &@"#schema".unions[0];

    NONE: void = 0,
    @"URIReference": @"tlb".@"URIReference" = 1,
    @"SignalReference": @"tlb".@"SignalReference" = 2,
    @"ImageSequenceReference": @"tlb".@"ImageSequenceReference" = 3,
    @"NullReference": @"tlb".@"NullReference" = 4,
};

pub const @"RateSpecifier" = union(enum(u8)) {
    pub const @"#kind" = flatbuffers.Kind.Union;
    pub const @"#root" = &@"#schema";
    pub const @"#type" = &@"#schema".unions[1];

    NONE: void = 0,
    @"IntRate": @"tlb".@"IntRate" = 1,
    @"RationalRate": @"tlb".@"RationalRate" = 2,
};

pub const @"SignalGenerator" = union(enum(u8)) {
    pub const @"#kind" = flatbuffers.Kind.Union;
    pub const @"#root" = &@"#schema";
    pub const @"#type" = &@"#schema".unions[2];

    NONE: void = 0,
    @"SineSignal": @"tlb".@"SineSignal" = 1,
    @"LinearRampSignal": @"tlb".@"LinearRampSignal" = 2,
};

pub const @"Bounds" = struct {
    pub const @"#kind" = flatbuffers.Kind.Table;
    pub const @"#root" = &@"#schema";
    pub const @"#type" = &@"#schema".tables[0];
    pub const @"#constructor" = struct {
@"bounds_type": @"tlb".@"BoundsType" = @enumFromInt(0), @"continuous": ?@"tlb".@"ContinuousBounds" = null, @"discrete": ?@"tlb".@"DiscreteBounds" = null, };

    @"#ref": flatbuffers.Ref,

    pub fn @"bounds_type"(@"#self": @"Bounds") @"tlb".@"BoundsType" {
        return flatbuffers.decodeEnumField(@"tlb".@"BoundsType", 0, @"#self".@"#ref", @enumFromInt(0));
    }

    pub fn @"continuous"(@"#self": @"Bounds") ?@"tlb".@"ContinuousBounds" {
        return flatbuffers.decodeStructField(@"tlb".@"ContinuousBounds", 1, @"#self".@"#ref");
    }

    pub fn @"discrete"(@"#self": @"Bounds") ?@"tlb".@"DiscreteBounds" {
        return flatbuffers.decodeStructField(@"tlb".@"DiscreteBounds", 2, @"#self".@"#ref");
    }

};

pub const @"Clip" = struct {
    pub const @"#kind" = flatbuffers.Kind.Table;
    pub const @"#root" = &@"#schema";
    pub const @"#type" = &@"#schema".tables[1];
    pub const @"#constructor" = struct {
@"name": ?[]const u8 = null, @"bounds": ?@"tlb".@"Bounds" = null, @"media": ?@"tlb".@"MediaReference" = null, @"metadata_hash": u64 = 0, @"markers": ?[]const @"tlb".@"Marker" = null, };

    @"#ref": flatbuffers.Ref,

    pub fn @"name"(@"#self": @"Clip") ?flatbuffers.String {
        return flatbuffers.decodeStringField(0, @"#self".@"#ref");
    }

    pub fn @"bounds"(@"#self": @"Clip") ?@"tlb".@"Bounds" {
        return flatbuffers.decodeTableField(@"tlb".@"Bounds", 1, @"#self".@"#ref");
    }

    pub fn @"media"(@"#self": @"Clip") ?@"tlb".@"MediaReference" {
        return flatbuffers.decodeTableField(@"tlb".@"MediaReference", 2, @"#self".@"#ref");
    }

    pub fn @"metadata_hash"(@"#self": @"Clip") u64 {
        return flatbuffers.decodeScalarField(u64, 3, @"#self".@"#ref", 0);
    }

    pub fn @"markers"(@"#self": @"Clip") ?flatbuffers.Vector(@"tlb".@"Marker") {
        return flatbuffers.decodeVectorField(@"tlb".@"Marker", 4, @"#self".@"#ref");
    }

};

pub const @"Collection" = struct {
    pub const @"#kind" = flatbuffers.Kind.Table;
    pub const @"#root" = &@"#schema";
    pub const @"#type" = &@"#schema".tables[2];
    pub const @"#constructor" = struct {
@"schema_version": u32 = 1, @"name": ?[]const u8 = null, @"description": ?[]const u8 = null, @"children": ?[]const @"tlb".@"CollectionItemWrapper" = null, @"metadata_map": ?@"tlb".@"MetadataMap" = null, };

    @"#ref": flatbuffers.Ref,

    pub fn @"schema_version"(@"#self": @"Collection") u32 {
        return flatbuffers.decodeScalarField(u32, 0, @"#self".@"#ref", 1);
    }

    pub fn @"name"(@"#self": @"Collection") ?flatbuffers.String {
        return flatbuffers.decodeStringField(1, @"#self".@"#ref");
    }

    pub fn @"description"(@"#self": @"Collection") ?flatbuffers.String {
        return flatbuffers.decodeStringField(2, @"#self".@"#ref");
    }

    pub fn @"children"(@"#self": @"Collection") ?flatbuffers.Vector(@"tlb".@"CollectionItemWrapper") {
        return flatbuffers.decodeVectorField(@"tlb".@"CollectionItemWrapper", 3, @"#self".@"#ref");
    }

    pub fn @"metadata_map"(@"#self": @"Collection") ?@"tlb".@"MetadataMap" {
        return flatbuffers.decodeTableField(@"tlb".@"MetadataMap", 4, @"#self".@"#ref");
    }

};

pub const @"CollectionItemWrapper" = struct {
    pub const @"#kind" = flatbuffers.Kind.Table;
    pub const @"#root" = &@"#schema";
    pub const @"#type" = &@"#schema".tables[3];
    pub const @"#constructor" = struct {
@"item_type": @"tlb".@"CollectionItemType" = @enumFromInt(0), @"timeline": ?@"tlb".@"Timeline" = null, @"track": ?@"tlb".@"Track" = null, @"stack": ?@"tlb".@"Stack" = null, @"clip": ?@"tlb".@"Clip" = null, @"gap": ?@"tlb".@"Gap" = null, @"warp": ?@"tlb".@"Warp" = null, @"transition": ?@"tlb".@"Transition" = null, };

    @"#ref": flatbuffers.Ref,

    pub fn @"item_type"(@"#self": @"CollectionItemWrapper") @"tlb".@"CollectionItemType" {
        return flatbuffers.decodeEnumField(@"tlb".@"CollectionItemType", 0, @"#self".@"#ref", @enumFromInt(0));
    }

    pub fn @"timeline"(@"#self": @"CollectionItemWrapper") ?@"tlb".@"Timeline" {
        return flatbuffers.decodeTableField(@"tlb".@"Timeline", 1, @"#self".@"#ref");
    }

    pub fn @"track"(@"#self": @"CollectionItemWrapper") ?@"tlb".@"Track" {
        return flatbuffers.decodeTableField(@"tlb".@"Track", 2, @"#self".@"#ref");
    }

    pub fn @"stack"(@"#self": @"CollectionItemWrapper") ?@"tlb".@"Stack" {
        return flatbuffers.decodeTableField(@"tlb".@"Stack", 3, @"#self".@"#ref");
    }

    pub fn @"clip"(@"#self": @"CollectionItemWrapper") ?@"tlb".@"Clip" {
        return flatbuffers.decodeTableField(@"tlb".@"Clip", 4, @"#self".@"#ref");
    }

    pub fn @"gap"(@"#self": @"CollectionItemWrapper") ?@"tlb".@"Gap" {
        return flatbuffers.decodeTableField(@"tlb".@"Gap", 5, @"#self".@"#ref");
    }

    pub fn @"warp"(@"#self": @"CollectionItemWrapper") ?@"tlb".@"Warp" {
        return flatbuffers.decodeTableField(@"tlb".@"Warp", 6, @"#self".@"#ref");
    }

    pub fn @"transition"(@"#self": @"CollectionItemWrapper") ?@"tlb".@"Transition" {
        return flatbuffers.decodeTableField(@"tlb".@"Transition", 7, @"#self".@"#ref");
    }

};

pub const @"ComposableWrapper" = struct {
    pub const @"#kind" = flatbuffers.Kind.Table;
    pub const @"#root" = &@"#schema";
    pub const @"#type" = &@"#schema".tables[4];
    pub const @"#constructor" = struct {
@"comp_type": @"tlb".@"ComposableType" = @enumFromInt(0), @"clip": ?@"tlb".@"Clip" = null, @"gap": ?@"tlb".@"Gap" = null, @"track": ?@"tlb".@"Track" = null, @"stack": ?@"tlb".@"Stack" = null, @"warp": ?@"tlb".@"Warp" = null, @"transition": ?@"tlb".@"Transition" = null, };

    @"#ref": flatbuffers.Ref,

    pub fn @"comp_type"(@"#self": @"ComposableWrapper") @"tlb".@"ComposableType" {
        return flatbuffers.decodeEnumField(@"tlb".@"ComposableType", 0, @"#self".@"#ref", @enumFromInt(0));
    }

    pub fn @"clip"(@"#self": @"ComposableWrapper") ?@"tlb".@"Clip" {
        return flatbuffers.decodeTableField(@"tlb".@"Clip", 1, @"#self".@"#ref");
    }

    pub fn @"gap"(@"#self": @"ComposableWrapper") ?@"tlb".@"Gap" {
        return flatbuffers.decodeTableField(@"tlb".@"Gap", 2, @"#self".@"#ref");
    }

    pub fn @"track"(@"#self": @"ComposableWrapper") ?@"tlb".@"Track" {
        return flatbuffers.decodeTableField(@"tlb".@"Track", 3, @"#self".@"#ref");
    }

    pub fn @"stack"(@"#self": @"ComposableWrapper") ?@"tlb".@"Stack" {
        return flatbuffers.decodeTableField(@"tlb".@"Stack", 4, @"#self".@"#ref");
    }

    pub fn @"warp"(@"#self": @"ComposableWrapper") ?@"tlb".@"Warp" {
        return flatbuffers.decodeTableField(@"tlb".@"Warp", 5, @"#self".@"#ref");
    }

    pub fn @"transition"(@"#self": @"ComposableWrapper") ?@"tlb".@"Transition" {
        return flatbuffers.decodeTableField(@"tlb".@"Transition", 6, @"#self".@"#ref");
    }

};

pub const @"DiscretePartitionDomainMap" = struct {
    pub const @"#kind" = flatbuffers.Kind.Table;
    pub const @"#root" = &@"#schema";
    pub const @"#type" = &@"#schema".tables[5];
    pub const @"#constructor" = struct {
@"picture": ?@"tlb".@"SampleIndexGenerator" = null, @"audio": ?@"tlb".@"SampleIndexGenerator" = null, };

    @"#ref": flatbuffers.Ref,

    pub fn @"picture"(@"#self": @"DiscretePartitionDomainMap") ?@"tlb".@"SampleIndexGenerator" {
        return flatbuffers.decodeTableField(@"tlb".@"SampleIndexGenerator", 0, @"#self".@"#ref");
    }

    pub fn @"audio"(@"#self": @"DiscretePartitionDomainMap") ?@"tlb".@"SampleIndexGenerator" {
        return flatbuffers.decodeTableField(@"tlb".@"SampleIndexGenerator", 1, @"#self".@"#ref");
    }

};

pub const @"Domain" = struct {
    pub const @"#kind" = flatbuffers.Kind.Table;
    pub const @"#root" = &@"#schema";
    pub const @"#type" = &@"#schema".tables[6];
    pub const @"#constructor" = struct {
@"domain_type": @"tlb".@"DomainType" = @enumFromInt(0), @"other_name": ?[]const u8 = null, };

    @"#ref": flatbuffers.Ref,

    pub fn @"domain_type"(@"#self": @"Domain") @"tlb".@"DomainType" {
        return flatbuffers.decodeEnumField(@"tlb".@"DomainType", 0, @"#self".@"#ref", @enumFromInt(0));
    }

    pub fn @"other_name"(@"#self": @"Domain") ?flatbuffers.String {
        return flatbuffers.decodeStringField(1, @"#self".@"#ref");
    }

};

pub const @"Gap" = struct {
    pub const @"#kind" = flatbuffers.Kind.Table;
    pub const @"#root" = &@"#schema";
    pub const @"#type" = &@"#schema".tables[7];
    pub const @"#constructor" = struct {
@"name": ?[]const u8 = null, @"bounds_start": f64 = 0, @"bounds_end": f64 = 0, @"markers": ?[]const @"tlb".@"Marker" = null, };

    @"#ref": flatbuffers.Ref,

    pub fn @"name"(@"#self": @"Gap") ?flatbuffers.String {
        return flatbuffers.decodeStringField(0, @"#self".@"#ref");
    }

    pub fn @"bounds_start"(@"#self": @"Gap") f64 {
        return flatbuffers.decodeScalarField(f64, 1, @"#self".@"#ref", 0);
    }

    pub fn @"bounds_end"(@"#self": @"Gap") f64 {
        return flatbuffers.decodeScalarField(f64, 2, @"#self".@"#ref", 0);
    }

    pub fn @"markers"(@"#self": @"Gap") ?flatbuffers.Vector(@"tlb".@"Marker") {
        return flatbuffers.decodeVectorField(@"tlb".@"Marker", 3, @"#self".@"#ref");
    }

};

pub const @"ImageSequenceReference" = struct {
    pub const @"#kind" = flatbuffers.Kind.Table;
    pub const @"#root" = &@"#schema";
    pub const @"#type" = &@"#schema".tables[8];
    pub const @"#constructor" = struct {
@"target_url_base": []const u8, @"name_prefix": ?[]const u8 = null, @"name_suffix": ?[]const u8 = null, @"start_frame": i32 = 1, @"frame_step": i32 = 1, @"frame_zero_padding": u8 = 0, @"rate": f64 = 24, @"missing_frame_policy": ?[]const u8 = null, };

    @"#ref": flatbuffers.Ref,

    pub fn @"target_url_base"(@"#self": @"ImageSequenceReference") flatbuffers.String {
        return flatbuffers.decodeStringField(0, @"#self".@"#ref") orelse
            @panic("missing tlb.ImageSequenceReference.target_url_base field");
    }

    pub fn @"name_prefix"(@"#self": @"ImageSequenceReference") ?flatbuffers.String {
        return flatbuffers.decodeStringField(1, @"#self".@"#ref");
    }

    pub fn @"name_suffix"(@"#self": @"ImageSequenceReference") ?flatbuffers.String {
        return flatbuffers.decodeStringField(2, @"#self".@"#ref");
    }

    pub fn @"start_frame"(@"#self": @"ImageSequenceReference") i32 {
        return flatbuffers.decodeScalarField(i32, 3, @"#self".@"#ref", 1);
    }

    pub fn @"frame_step"(@"#self": @"ImageSequenceReference") i32 {
        return flatbuffers.decodeScalarField(i32, 4, @"#self".@"#ref", 1);
    }

    pub fn @"frame_zero_padding"(@"#self": @"ImageSequenceReference") u8 {
        return flatbuffers.decodeScalarField(u8, 5, @"#self".@"#ref", 0);
    }

    pub fn @"rate"(@"#self": @"ImageSequenceReference") f64 {
        return flatbuffers.decodeScalarField(f64, 6, @"#self".@"#ref", 24);
    }

    pub fn @"missing_frame_policy"(@"#self": @"ImageSequenceReference") ?flatbuffers.String {
        return flatbuffers.decodeStringField(7, @"#self".@"#ref");
    }

};

pub const @"IntRate" = struct {
    pub const @"#kind" = flatbuffers.Kind.Table;
    pub const @"#root" = &@"#schema";
    pub const @"#type" = &@"#schema".tables[9];
    pub const @"#constructor" = struct {
@"value": u32 = 0, };

    @"#ref": flatbuffers.Ref,

    pub fn @"value"(@"#self": @"IntRate") u32 {
        return flatbuffers.decodeScalarField(u32, 0, @"#self".@"#ref", 0);
    }

};

pub const @"LinearRampSignal" = struct {
    pub const @"#kind" = flatbuffers.Kind.Table;
    pub const @"#root" = &@"#schema";
    pub const @"#type" = &@"#schema".tables[10];
    pub const @"#constructor" = struct {
};

    @"#ref": flatbuffers.Ref,

};

pub const @"MappingAffine" = struct {
    pub const @"#kind" = flatbuffers.Kind.Table;
    pub const @"#root" = &@"#schema";
    pub const @"#type" = &@"#schema".tables[11];
    pub const @"#constructor" = struct {
@"input_bounds_start": f64 = 0, @"input_bounds_end": f64 = 0, @"transform": ?@"tlb".@"AffineTransform1D" = null, };

    @"#ref": flatbuffers.Ref,

    pub fn @"input_bounds_start"(@"#self": @"MappingAffine") f64 {
        return flatbuffers.decodeScalarField(f64, 0, @"#self".@"#ref", 0);
    }

    pub fn @"input_bounds_end"(@"#self": @"MappingAffine") f64 {
        return flatbuffers.decodeScalarField(f64, 1, @"#self".@"#ref", 0);
    }

    pub fn @"transform"(@"#self": @"MappingAffine") ?@"tlb".@"AffineTransform1D" {
        return flatbuffers.decodeStructField(@"tlb".@"AffineTransform1D", 2, @"#self".@"#ref");
    }

};

pub const @"MappingLinear" = struct {
    pub const @"#kind" = flatbuffers.Kind.Table;
    pub const @"#root" = &@"#schema";
    pub const @"#type" = &@"#schema".tables[12];
    pub const @"#constructor" = struct {
@"input_bounds_start": f64 = 0, @"input_bounds_end": f64 = 0, @"knots": ?[]const @"tlb".@"ControlPoint" = null, };

    @"#ref": flatbuffers.Ref,

    pub fn @"input_bounds_start"(@"#self": @"MappingLinear") f64 {
        return flatbuffers.decodeScalarField(f64, 0, @"#self".@"#ref", 0);
    }

    pub fn @"input_bounds_end"(@"#self": @"MappingLinear") f64 {
        return flatbuffers.decodeScalarField(f64, 1, @"#self".@"#ref", 0);
    }

    pub fn @"knots"(@"#self": @"MappingLinear") ?flatbuffers.Vector(@"tlb".@"ControlPoint") {
        return flatbuffers.decodeVectorField(@"tlb".@"ControlPoint", 2, @"#self".@"#ref");
    }

};

pub const @"MappingWrapper" = struct {
    pub const @"#kind" = flatbuffers.Kind.Table;
    pub const @"#root" = &@"#schema";
    pub const @"#type" = &@"#schema".tables[13];
    pub const @"#constructor" = struct {
@"mapping_type": @"tlb".@"MappingType" = @enumFromInt(0), @"affine": ?@"tlb".@"MappingAffine" = null, @"linear": ?@"tlb".@"MappingLinear" = null, };

    @"#ref": flatbuffers.Ref,

    pub fn @"mapping_type"(@"#self": @"MappingWrapper") @"tlb".@"MappingType" {
        return flatbuffers.decodeEnumField(@"tlb".@"MappingType", 0, @"#self".@"#ref", @enumFromInt(0));
    }

    pub fn @"affine"(@"#self": @"MappingWrapper") ?@"tlb".@"MappingAffine" {
        return flatbuffers.decodeTableField(@"tlb".@"MappingAffine", 1, @"#self".@"#ref");
    }

    pub fn @"linear"(@"#self": @"MappingWrapper") ?@"tlb".@"MappingLinear" {
        return flatbuffers.decodeTableField(@"tlb".@"MappingLinear", 2, @"#self".@"#ref");
    }

};

pub const @"Marker" = struct {
    pub const @"#kind" = flatbuffers.Kind.Table;
    pub const @"#root" = &@"#schema";
    pub const @"#type" = &@"#schema".tables[14];
    pub const @"#constructor" = struct {
@"name": ?[]const u8 = null, @"marked_range_start": f64 = 0, @"marked_range_end": f64 = 0, @"color": []const u8, @"comment": ?[]const u8 = null, };

    @"#ref": flatbuffers.Ref,

    pub fn @"name"(@"#self": @"Marker") ?flatbuffers.String {
        return flatbuffers.decodeStringField(0, @"#self".@"#ref");
    }

    pub fn @"marked_range_start"(@"#self": @"Marker") f64 {
        return flatbuffers.decodeScalarField(f64, 1, @"#self".@"#ref", 0);
    }

    pub fn @"marked_range_end"(@"#self": @"Marker") f64 {
        return flatbuffers.decodeScalarField(f64, 2, @"#self".@"#ref", 0);
    }

    pub fn @"color"(@"#self": @"Marker") flatbuffers.String {
        return flatbuffers.decodeStringField(3, @"#self".@"#ref") orelse
            @panic("missing tlb.Marker.color field");
    }

    pub fn @"comment"(@"#self": @"Marker") ?flatbuffers.String {
        return flatbuffers.decodeStringField(4, @"#self".@"#ref");
    }

};

pub const @"MediaReference" = struct {
    pub const @"#kind" = flatbuffers.Kind.Table;
    pub const @"#root" = &@"#schema";
    pub const @"#type" = &@"#schema".tables[15];
    pub const @"#constructor" = struct {
@"data_reference_type": @"tlb".@"MediaDataReference" = .NONE, @"bounds": ?@"tlb".@"Bounds" = null, @"domain": ?@"tlb".@"Domain" = null, @"discrete_partition": ?@"tlb".@"SampleIndexGenerator" = null, @"interpolating": @"tlb".@"MediaInterpolationType" = @enumFromInt(0), };

    @"#ref": flatbuffers.Ref,

    pub fn @"data_reference_type"(@"#self": @"MediaReference") @"tlb".@"MediaDataReference" {
        return flatbuffers.decodeUnionField(@"tlb".@"MediaDataReference", 0, 1, @"#self".@"#ref");
    }

    pub fn @"bounds"(@"#self": @"MediaReference") ?@"tlb".@"Bounds" {
        return flatbuffers.decodeTableField(@"tlb".@"Bounds", 2, @"#self".@"#ref");
    }

    pub fn @"domain"(@"#self": @"MediaReference") ?@"tlb".@"Domain" {
        return flatbuffers.decodeTableField(@"tlb".@"Domain", 3, @"#self".@"#ref");
    }

    pub fn @"discrete_partition"(@"#self": @"MediaReference") ?@"tlb".@"SampleIndexGenerator" {
        return flatbuffers.decodeTableField(@"tlb".@"SampleIndexGenerator", 4, @"#self".@"#ref");
    }

    pub fn @"interpolating"(@"#self": @"MediaReference") @"tlb".@"MediaInterpolationType" {
        return flatbuffers.decodeEnumField(@"tlb".@"MediaInterpolationType", 5, @"#self".@"#ref", @enumFromInt(0));
    }

};

pub const @"MetadataBlock" = struct {
    pub const @"#kind" = flatbuffers.Kind.Table;
    pub const @"#root" = &@"#schema";
    pub const @"#type" = &@"#schema".tables[16];
    pub const @"#constructor" = struct {
@"keys": ?[]const []const u8 = null, @"types": ?[]const i8 = null, @"scalars": ?[]const @"tlb".@"PackedScalar" = null, @"string_values": ?[]const []const u8 = null, @"string_indices": ?[]const u32 = null, @"nested_blocks": ?[]const @"tlb".@"MetadataBlock" = null, @"nested_indices": ?[]const u32 = null, @"array_blocks": ?[]const @"tlb".@"MetadataBlock" = null, @"array_indices": ?[]const u32 = null, };

    @"#ref": flatbuffers.Ref,

    pub fn @"keys"(@"#self": @"MetadataBlock") ?flatbuffers.Vector(flatbuffers.String) {
        return flatbuffers.decodeVectorField(flatbuffers.String, 0, @"#self".@"#ref");
    }

    pub fn @"types"(@"#self": @"MetadataBlock") ?flatbuffers.Vector(i8) {
        return flatbuffers.decodeVectorField(i8, 1, @"#self".@"#ref");
    }

    pub fn @"scalars"(@"#self": @"MetadataBlock") ?flatbuffers.Vector(@"tlb".@"PackedScalar") {
        return flatbuffers.decodeVectorField(@"tlb".@"PackedScalar", 2, @"#self".@"#ref");
    }

    pub fn @"string_values"(@"#self": @"MetadataBlock") ?flatbuffers.Vector(flatbuffers.String) {
        return flatbuffers.decodeVectorField(flatbuffers.String, 3, @"#self".@"#ref");
    }

    pub fn @"string_indices"(@"#self": @"MetadataBlock") ?flatbuffers.Vector(u32) {
        return flatbuffers.decodeVectorField(u32, 4, @"#self".@"#ref");
    }

    pub fn @"nested_blocks"(@"#self": @"MetadataBlock") ?flatbuffers.Vector(@"tlb".@"MetadataBlock") {
        return flatbuffers.decodeVectorField(@"tlb".@"MetadataBlock", 5, @"#self".@"#ref");
    }

    pub fn @"nested_indices"(@"#self": @"MetadataBlock") ?flatbuffers.Vector(u32) {
        return flatbuffers.decodeVectorField(u32, 6, @"#self".@"#ref");
    }

    pub fn @"array_blocks"(@"#self": @"MetadataBlock") ?flatbuffers.Vector(@"tlb".@"MetadataBlock") {
        return flatbuffers.decodeVectorField(@"tlb".@"MetadataBlock", 7, @"#self".@"#ref");
    }

    pub fn @"array_indices"(@"#self": @"MetadataBlock") ?flatbuffers.Vector(u32) {
        return flatbuffers.decodeVectorField(u32, 8, @"#self".@"#ref");
    }

};

pub const @"MetadataMap" = struct {
    pub const @"#kind" = flatbuffers.Kind.Table;
    pub const @"#root" = &@"#schema";
    pub const @"#type" = &@"#schema".tables[17];
    pub const @"#constructor" = struct {
@"hashes": ?[]const []const u8 = null, @"block_offsets": ?[]const u32 = null, @"block_lengths": ?[]const u32 = null, @"all_keys": ?[]const []const u8 = null, @"all_types": ?[]const u8 = null, @"all_scalars": ?[]const @"tlb".@"PackedScalar" = null, @"string_values": ?[]const []const u8 = null, @"string_key_indices": ?[]const u32 = null, @"string_value_indices": ?[]const u32 = null, @"nested_blocks": ?[]const @"tlb".@"MetadataBlock" = null, @"nested_key_indices": ?[]const u32 = null, @"nested_block_indices": ?[]const u32 = null, };

    @"#ref": flatbuffers.Ref,

    pub fn @"hashes"(@"#self": @"MetadataMap") ?flatbuffers.Vector(flatbuffers.String) {
        return flatbuffers.decodeVectorField(flatbuffers.String, 0, @"#self".@"#ref");
    }

    pub fn @"block_offsets"(@"#self": @"MetadataMap") ?flatbuffers.Vector(u32) {
        return flatbuffers.decodeVectorField(u32, 1, @"#self".@"#ref");
    }

    pub fn @"block_lengths"(@"#self": @"MetadataMap") ?flatbuffers.Vector(u32) {
        return flatbuffers.decodeVectorField(u32, 2, @"#self".@"#ref");
    }

    pub fn @"all_keys"(@"#self": @"MetadataMap") ?flatbuffers.Vector(flatbuffers.String) {
        return flatbuffers.decodeVectorField(flatbuffers.String, 3, @"#self".@"#ref");
    }

    pub fn @"all_types"(@"#self": @"MetadataMap") ?flatbuffers.Vector(u8) {
        return flatbuffers.decodeVectorField(u8, 4, @"#self".@"#ref");
    }

    pub fn @"all_scalars"(@"#self": @"MetadataMap") ?flatbuffers.Vector(@"tlb".@"PackedScalar") {
        return flatbuffers.decodeVectorField(@"tlb".@"PackedScalar", 5, @"#self".@"#ref");
    }

    pub fn @"string_values"(@"#self": @"MetadataMap") ?flatbuffers.Vector(flatbuffers.String) {
        return flatbuffers.decodeVectorField(flatbuffers.String, 6, @"#self".@"#ref");
    }

    pub fn @"string_key_indices"(@"#self": @"MetadataMap") ?flatbuffers.Vector(u32) {
        return flatbuffers.decodeVectorField(u32, 7, @"#self".@"#ref");
    }

    pub fn @"string_value_indices"(@"#self": @"MetadataMap") ?flatbuffers.Vector(u32) {
        return flatbuffers.decodeVectorField(u32, 8, @"#self".@"#ref");
    }

    pub fn @"nested_blocks"(@"#self": @"MetadataMap") ?flatbuffers.Vector(@"tlb".@"MetadataBlock") {
        return flatbuffers.decodeVectorField(@"tlb".@"MetadataBlock", 9, @"#self".@"#ref");
    }

    pub fn @"nested_key_indices"(@"#self": @"MetadataMap") ?flatbuffers.Vector(u32) {
        return flatbuffers.decodeVectorField(u32, 10, @"#self".@"#ref");
    }

    pub fn @"nested_block_indices"(@"#self": @"MetadataMap") ?flatbuffers.Vector(u32) {
        return flatbuffers.decodeVectorField(u32, 11, @"#self".@"#ref");
    }

};

pub const @"NullReference" = struct {
    pub const @"#kind" = flatbuffers.Kind.Table;
    pub const @"#root" = &@"#schema";
    pub const @"#type" = &@"#schema".tables[18];
    pub const @"#constructor" = struct {
};

    @"#ref": flatbuffers.Ref,

};

pub const @"RationalRate" = struct {
    pub const @"#kind" = flatbuffers.Kind.Table;
    pub const @"#root" = &@"#schema";
    pub const @"#type" = &@"#schema".tables[19];
    pub const @"#constructor" = struct {
@"num": u32 = 0, @"den": u32 = 0, };

    @"#ref": flatbuffers.Ref,

    pub fn @"num"(@"#self": @"RationalRate") u32 {
        return flatbuffers.decodeScalarField(u32, 0, @"#self".@"#ref", 0);
    }

    pub fn @"den"(@"#self": @"RationalRate") u32 {
        return flatbuffers.decodeScalarField(u32, 1, @"#self".@"#ref", 0);
    }

};

pub const @"SampleIndexGenerator" = struct {
    pub const @"#kind" = flatbuffers.Kind.Table;
    pub const @"#root" = &@"#schema";
    pub const @"#type" = &@"#schema".tables[20];
    pub const @"#constructor" = struct {
@"sample_rate_hz_type": @"tlb".@"RateSpecifier" = .NONE, @"start_index": i64 = 0, };

    @"#ref": flatbuffers.Ref,

    pub fn @"sample_rate_hz_type"(@"#self": @"SampleIndexGenerator") @"tlb".@"RateSpecifier" {
        return flatbuffers.decodeUnionField(@"tlb".@"RateSpecifier", 0, 1, @"#self".@"#ref");
    }

    pub fn @"start_index"(@"#self": @"SampleIndexGenerator") i64 {
        return flatbuffers.decodeScalarField(i64, 2, @"#self".@"#ref", 0);
    }

};

pub const @"SignalReference" = struct {
    pub const @"#kind" = flatbuffers.Kind.Table;
    pub const @"#root" = &@"#schema";
    pub const @"#type" = &@"#schema".tables[21];
    pub const @"#constructor" = struct {
@"signal_generator_type": @"tlb".@"SignalGenerator" = .NONE, };

    @"#ref": flatbuffers.Ref,

    pub fn @"signal_generator_type"(@"#self": @"SignalReference") @"tlb".@"SignalGenerator" {
        return flatbuffers.decodeUnionField(@"tlb".@"SignalGenerator", 0, 1, @"#self".@"#ref");
    }

};

pub const @"SineSignal" = struct {
    pub const @"#kind" = flatbuffers.Kind.Table;
    pub const @"#root" = &@"#schema";
    pub const @"#type" = &@"#schema".tables[22];
    pub const @"#constructor" = struct {
@"frequency_hz": f64 = 0, };

    @"#ref": flatbuffers.Ref,

    pub fn @"frequency_hz"(@"#self": @"SineSignal") f64 {
        return flatbuffers.decodeScalarField(f64, 0, @"#self".@"#ref", 0);
    }

};

pub const @"Stack" = struct {
    pub const @"#kind" = flatbuffers.Kind.Table;
    pub const @"#root" = &@"#schema";
    pub const @"#type" = &@"#schema".tables[23];
    pub const @"#constructor" = struct {
@"name": ?[]const u8 = null, @"bounds": ?@"tlb".@"Bounds" = null, @"children": ?[]const @"tlb".@"ComposableWrapper" = null, @"markers": ?[]const @"tlb".@"Marker" = null, };

    @"#ref": flatbuffers.Ref,

    pub fn @"name"(@"#self": @"Stack") ?flatbuffers.String {
        return flatbuffers.decodeStringField(0, @"#self".@"#ref");
    }

    pub fn @"bounds"(@"#self": @"Stack") ?@"tlb".@"Bounds" {
        return flatbuffers.decodeTableField(@"tlb".@"Bounds", 1, @"#self".@"#ref");
    }

    pub fn @"children"(@"#self": @"Stack") ?flatbuffers.Vector(@"tlb".@"ComposableWrapper") {
        return flatbuffers.decodeVectorField(@"tlb".@"ComposableWrapper", 2, @"#self".@"#ref");
    }

    pub fn @"markers"(@"#self": @"Stack") ?flatbuffers.Vector(@"tlb".@"Marker") {
        return flatbuffers.decodeVectorField(@"tlb".@"Marker", 3, @"#self".@"#ref");
    }

};

pub const @"Timeline" = struct {
    pub const @"#kind" = flatbuffers.Kind.Table;
    pub const @"#root" = &@"#schema";
    pub const @"#type" = &@"#schema".tables[24];
    pub const @"#constructor" = struct {
@"schema_version": u32 = 1, @"name": ?[]const u8 = null, @"children": ?[]const @"tlb".@"ComposableWrapper" = null, @"presentation_space_discrete_partitions": ?@"tlb".@"DiscretePartitionDomainMap" = null, @"metadata_map": ?@"tlb".@"MetadataMap" = null, @"markers": ?[]const @"tlb".@"Marker" = null, };

    @"#ref": flatbuffers.Ref,

    pub fn @"schema_version"(@"#self": @"Timeline") u32 {
        return flatbuffers.decodeScalarField(u32, 0, @"#self".@"#ref", 1);
    }

    pub fn @"name"(@"#self": @"Timeline") ?flatbuffers.String {
        return flatbuffers.decodeStringField(1, @"#self".@"#ref");
    }

    pub fn @"children"(@"#self": @"Timeline") ?flatbuffers.Vector(@"tlb".@"ComposableWrapper") {
        return flatbuffers.decodeVectorField(@"tlb".@"ComposableWrapper", 2, @"#self".@"#ref");
    }

    pub fn @"presentation_space_discrete_partitions"(@"#self": @"Timeline") ?@"tlb".@"DiscretePartitionDomainMap" {
        return flatbuffers.decodeTableField(@"tlb".@"DiscretePartitionDomainMap", 3, @"#self".@"#ref");
    }

    pub fn @"metadata_map"(@"#self": @"Timeline") ?@"tlb".@"MetadataMap" {
        return flatbuffers.decodeTableField(@"tlb".@"MetadataMap", 4, @"#self".@"#ref");
    }

    pub fn @"markers"(@"#self": @"Timeline") ?flatbuffers.Vector(@"tlb".@"Marker") {
        return flatbuffers.decodeVectorField(@"tlb".@"Marker", 5, @"#self".@"#ref");
    }

};

pub const @"Topology" = struct {
    pub const @"#kind" = flatbuffers.Kind.Table;
    pub const @"#root" = &@"#schema";
    pub const @"#type" = &@"#schema".tables[25];
    pub const @"#constructor" = struct {
@"mappings": ?[]const @"tlb".@"MappingWrapper" = null, };

    @"#ref": flatbuffers.Ref,

    pub fn @"mappings"(@"#self": @"Topology") ?flatbuffers.Vector(@"tlb".@"MappingWrapper") {
        return flatbuffers.decodeVectorField(@"tlb".@"MappingWrapper", 0, @"#self".@"#ref");
    }

};

pub const @"Track" = struct {
    pub const @"#kind" = flatbuffers.Kind.Table;
    pub const @"#root" = &@"#schema";
    pub const @"#type" = &@"#schema".tables[26];
    pub const @"#constructor" = struct {
@"name": ?[]const u8 = null, @"bounds": ?@"tlb".@"Bounds" = null, @"children": ?[]const @"tlb".@"ComposableWrapper" = null, @"markers": ?[]const @"tlb".@"Marker" = null, };

    @"#ref": flatbuffers.Ref,

    pub fn @"name"(@"#self": @"Track") ?flatbuffers.String {
        return flatbuffers.decodeStringField(0, @"#self".@"#ref");
    }

    pub fn @"bounds"(@"#self": @"Track") ?@"tlb".@"Bounds" {
        return flatbuffers.decodeTableField(@"tlb".@"Bounds", 1, @"#self".@"#ref");
    }

    pub fn @"children"(@"#self": @"Track") ?flatbuffers.Vector(@"tlb".@"ComposableWrapper") {
        return flatbuffers.decodeVectorField(@"tlb".@"ComposableWrapper", 2, @"#self".@"#ref");
    }

    pub fn @"markers"(@"#self": @"Track") ?flatbuffers.Vector(@"tlb".@"Marker") {
        return flatbuffers.decodeVectorField(@"tlb".@"Marker", 3, @"#self".@"#ref");
    }

};

pub const @"Transition" = struct {
    pub const @"#kind" = flatbuffers.Kind.Table;
    pub const @"#root" = &@"#schema";
    pub const @"#type" = &@"#schema".tables[27];
    pub const @"#constructor" = struct {
@"name": ?[]const u8 = null, @"container": ?@"tlb".@"Stack" = null, @"kind": []const u8, @"bounds_start": f64 = 0, @"bounds_end": f64 = 0, @"has_bounds": bool = false, };

    @"#ref": flatbuffers.Ref,

    pub fn @"name"(@"#self": @"Transition") ?flatbuffers.String {
        return flatbuffers.decodeStringField(0, @"#self".@"#ref");
    }

    pub fn @"container"(@"#self": @"Transition") ?@"tlb".@"Stack" {
        return flatbuffers.decodeTableField(@"tlb".@"Stack", 1, @"#self".@"#ref");
    }

    pub fn @"kind"(@"#self": @"Transition") flatbuffers.String {
        return flatbuffers.decodeStringField(2, @"#self".@"#ref") orelse
            @panic("missing tlb.Transition.kind field");
    }

    pub fn @"bounds_start"(@"#self": @"Transition") f64 {
        return flatbuffers.decodeScalarField(f64, 3, @"#self".@"#ref", 0);
    }

    pub fn @"bounds_end"(@"#self": @"Transition") f64 {
        return flatbuffers.decodeScalarField(f64, 4, @"#self".@"#ref", 0);
    }

    pub fn @"has_bounds"(@"#self": @"Transition") bool {
        return flatbuffers.decodeScalarField(bool, 5, @"#self".@"#ref", false);
    }

};

pub const @"URIReference" = struct {
    pub const @"#kind" = flatbuffers.Kind.Table;
    pub const @"#root" = &@"#schema";
    pub const @"#type" = &@"#schema".tables[28];
    pub const @"#constructor" = struct {
@"target_uri": []const u8, };

    @"#ref": flatbuffers.Ref,

    pub fn @"target_uri"(@"#self": @"URIReference") flatbuffers.String {
        return flatbuffers.decodeStringField(0, @"#self".@"#ref") orelse
            @panic("missing tlb.URIReference.target_uri field");
    }

};

pub const @"Warp" = struct {
    pub const @"#kind" = flatbuffers.Kind.Table;
    pub const @"#root" = &@"#schema";
    pub const @"#type" = &@"#schema".tables[29];
    pub const @"#constructor" = struct {
@"name": ?[]const u8 = null, @"child": ?@"tlb".@"ComposableWrapper" = null, @"transform": ?@"tlb".@"Topology" = null, };

    @"#ref": flatbuffers.Ref,

    pub fn @"name"(@"#self": @"Warp") ?flatbuffers.String {
        return flatbuffers.decodeStringField(0, @"#self".@"#ref");
    }

    pub fn @"child"(@"#self": @"Warp") ?@"tlb".@"ComposableWrapper" {
        return flatbuffers.decodeTableField(@"tlb".@"ComposableWrapper", 1, @"#self".@"#ref");
    }

    pub fn @"transform"(@"#self": @"Warp") ?@"tlb".@"Topology" {
        return flatbuffers.decodeTableField(@"tlb".@"Topology", 2, @"#self".@"#ref");
    }

};

};
