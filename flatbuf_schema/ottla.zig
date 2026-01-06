const std = @import("std");

const flatbuffers = @import("flatbuffers");

const @"#schema": flatbuffers.types.Schema = @import("ottla.zon");

pub const ottla = struct {
pub const @"BoundsType" = enum(i8) {
    pub const @"#kind" = flatbuffers.Kind.Enum;
    pub const @"#root" = &@"#schema";
    pub const @"#type" = &@"#schema".enums[0];

    @"Continuous" = 0,
    @"Discrete" = 1,
};

pub const @"ComposableType" = enum(i8) {
    pub const @"#kind" = flatbuffers.Kind.Enum;
    pub const @"#root" = &@"#schema";
    pub const @"#type" = &@"#schema".enums[1];

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
    pub const @"#type" = &@"#schema".enums[2];

    @"Time" = 0,
    @"Picture" = 1,
    @"Audio" = 2,
    @"Metadata" = 3,
    @"Other" = 4,
};

pub const @"MappingType" = enum(i8) {
    pub const @"#kind" = flatbuffers.Kind.Enum;
    pub const @"#root" = &@"#schema";
    pub const @"#type" = &@"#schema".enums[3];

    @"Affine" = 0,
    @"Linear" = 1,
    @"Empty" = 2,
};

pub const @"MediaInterpolationType" = enum(i8) {
    pub const @"#kind" = flatbuffers.Kind.Enum;
    pub const @"#root" = &@"#schema";
    pub const @"#type" = &@"#schema".enums[4];

    @"Interpolate" = 0,
    @"Snap" = 1,
    @"DefaultFromDomain" = 2,
};

pub const @"MetadataType" = enum(i8) {
    pub const @"#kind" = flatbuffers.Kind.Enum;
    pub const @"#root" = &@"#schema";
    pub const @"#type" = &@"#schema".enums[5];

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
    @"URIReference": @"ottla".@"URIReference" = 1,
    @"SignalReference": @"ottla".@"SignalReference" = 2,
    @"NullReference": @"ottla".@"NullReference" = 3,
};

pub const @"RateSpecifier" = union(enum(u8)) {
    pub const @"#kind" = flatbuffers.Kind.Union;
    pub const @"#root" = &@"#schema";
    pub const @"#type" = &@"#schema".unions[1];

    NONE: void = 0,
    @"IntRate": @"ottla".@"IntRate" = 1,
    @"RationalRate": @"ottla".@"RationalRate" = 2,
};

pub const @"SignalGenerator" = union(enum(u8)) {
    pub const @"#kind" = flatbuffers.Kind.Union;
    pub const @"#root" = &@"#schema";
    pub const @"#type" = &@"#schema".unions[2];

    NONE: void = 0,
    @"SineSignal": @"ottla".@"SineSignal" = 1,
    @"LinearRampSignal": @"ottla".@"LinearRampSignal" = 2,
};

pub const @"Bounds" = struct {
    pub const @"#kind" = flatbuffers.Kind.Table;
    pub const @"#root" = &@"#schema";
    pub const @"#type" = &@"#schema".tables[0];
    pub const @"#constructor" = struct {
@"bounds_type": @"ottla".@"BoundsType" = @enumFromInt(0), @"continuous": ?@"ottla".@"ContinuousBounds" = null, @"discrete": ?@"ottla".@"DiscreteBounds" = null, };

    @"#ref": flatbuffers.Ref,

    pub fn @"bounds_type"(@"#self": @"Bounds") @"ottla".@"BoundsType" {
        return flatbuffers.decodeEnumField(@"ottla".@"BoundsType", 0, @"#self".@"#ref", @enumFromInt(0));
    }

    pub fn @"continuous"(@"#self": @"Bounds") ?@"ottla".@"ContinuousBounds" {
        return flatbuffers.decodeStructField(@"ottla".@"ContinuousBounds", 1, @"#self".@"#ref");
    }

    pub fn @"discrete"(@"#self": @"Bounds") ?@"ottla".@"DiscreteBounds" {
        return flatbuffers.decodeStructField(@"ottla".@"DiscreteBounds", 2, @"#self".@"#ref");
    }

};

pub const @"Clip" = struct {
    pub const @"#kind" = flatbuffers.Kind.Table;
    pub const @"#root" = &@"#schema";
    pub const @"#type" = &@"#schema".tables[1];
    pub const @"#constructor" = struct {
@"name": ?[]const u8 = null, @"bounds": ?@"ottla".@"Bounds" = null, @"media": ?@"ottla".@"MediaReference" = null, @"metadata_hash": ?[]const u8 = null, };

    @"#ref": flatbuffers.Ref,

    pub fn @"name"(@"#self": @"Clip") ?flatbuffers.String {
        return flatbuffers.decodeStringField(0, @"#self".@"#ref");
    }

    pub fn @"bounds"(@"#self": @"Clip") ?@"ottla".@"Bounds" {
        return flatbuffers.decodeTableField(@"ottla".@"Bounds", 1, @"#self".@"#ref");
    }

    pub fn @"media"(@"#self": @"Clip") ?@"ottla".@"MediaReference" {
        return flatbuffers.decodeTableField(@"ottla".@"MediaReference", 2, @"#self".@"#ref");
    }

    pub fn @"metadata_hash"(@"#self": @"Clip") ?flatbuffers.String {
        return flatbuffers.decodeStringField(3, @"#self".@"#ref");
    }

};

pub const @"ComposableWrapper" = struct {
    pub const @"#kind" = flatbuffers.Kind.Table;
    pub const @"#root" = &@"#schema";
    pub const @"#type" = &@"#schema".tables[2];
    pub const @"#constructor" = struct {
@"comp_type": @"ottla".@"ComposableType" = @enumFromInt(0), @"clip": ?@"ottla".@"Clip" = null, @"gap": ?@"ottla".@"Gap" = null, @"track": ?@"ottla".@"Track" = null, @"stack": ?@"ottla".@"Stack" = null, @"warp": ?@"ottla".@"Warp" = null, @"transition": ?@"ottla".@"Transition" = null, };

    @"#ref": flatbuffers.Ref,

    pub fn @"comp_type"(@"#self": @"ComposableWrapper") @"ottla".@"ComposableType" {
        return flatbuffers.decodeEnumField(@"ottla".@"ComposableType", 0, @"#self".@"#ref", @enumFromInt(0));
    }

    pub fn @"clip"(@"#self": @"ComposableWrapper") ?@"ottla".@"Clip" {
        return flatbuffers.decodeTableField(@"ottla".@"Clip", 1, @"#self".@"#ref");
    }

    pub fn @"gap"(@"#self": @"ComposableWrapper") ?@"ottla".@"Gap" {
        return flatbuffers.decodeTableField(@"ottla".@"Gap", 2, @"#self".@"#ref");
    }

    pub fn @"track"(@"#self": @"ComposableWrapper") ?@"ottla".@"Track" {
        return flatbuffers.decodeTableField(@"ottla".@"Track", 3, @"#self".@"#ref");
    }

    pub fn @"stack"(@"#self": @"ComposableWrapper") ?@"ottla".@"Stack" {
        return flatbuffers.decodeTableField(@"ottla".@"Stack", 4, @"#self".@"#ref");
    }

    pub fn @"warp"(@"#self": @"ComposableWrapper") ?@"ottla".@"Warp" {
        return flatbuffers.decodeTableField(@"ottla".@"Warp", 5, @"#self".@"#ref");
    }

    pub fn @"transition"(@"#self": @"ComposableWrapper") ?@"ottla".@"Transition" {
        return flatbuffers.decodeTableField(@"ottla".@"Transition", 6, @"#self".@"#ref");
    }

};

pub const @"DiscretePartitionDomainMap" = struct {
    pub const @"#kind" = flatbuffers.Kind.Table;
    pub const @"#root" = &@"#schema";
    pub const @"#type" = &@"#schema".tables[3];
    pub const @"#constructor" = struct {
@"picture": ?@"ottla".@"SampleIndexGenerator" = null, @"audio": ?@"ottla".@"SampleIndexGenerator" = null, };

    @"#ref": flatbuffers.Ref,

    pub fn @"picture"(@"#self": @"DiscretePartitionDomainMap") ?@"ottla".@"SampleIndexGenerator" {
        return flatbuffers.decodeTableField(@"ottla".@"SampleIndexGenerator", 0, @"#self".@"#ref");
    }

    pub fn @"audio"(@"#self": @"DiscretePartitionDomainMap") ?@"ottla".@"SampleIndexGenerator" {
        return flatbuffers.decodeTableField(@"ottla".@"SampleIndexGenerator", 1, @"#self".@"#ref");
    }

};

pub const @"Domain" = struct {
    pub const @"#kind" = flatbuffers.Kind.Table;
    pub const @"#root" = &@"#schema";
    pub const @"#type" = &@"#schema".tables[4];
    pub const @"#constructor" = struct {
@"domain_type": @"ottla".@"DomainType" = @enumFromInt(0), @"other_name": ?[]const u8 = null, };

    @"#ref": flatbuffers.Ref,

    pub fn @"domain_type"(@"#self": @"Domain") @"ottla".@"DomainType" {
        return flatbuffers.decodeEnumField(@"ottla".@"DomainType", 0, @"#self".@"#ref", @enumFromInt(0));
    }

    pub fn @"other_name"(@"#self": @"Domain") ?flatbuffers.String {
        return flatbuffers.decodeStringField(1, @"#self".@"#ref");
    }

};

pub const @"Gap" = struct {
    pub const @"#kind" = flatbuffers.Kind.Table;
    pub const @"#root" = &@"#schema";
    pub const @"#type" = &@"#schema".tables[5];
    pub const @"#constructor" = struct {
@"name": ?[]const u8 = null, @"bounds_start": f64 = 0, @"bounds_end": f64 = 0, };

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

};

pub const @"IntRate" = struct {
    pub const @"#kind" = flatbuffers.Kind.Table;
    pub const @"#root" = &@"#schema";
    pub const @"#type" = &@"#schema".tables[6];
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
    pub const @"#type" = &@"#schema".tables[7];
    pub const @"#constructor" = struct {
};

    @"#ref": flatbuffers.Ref,

};

pub const @"MappingAffine" = struct {
    pub const @"#kind" = flatbuffers.Kind.Table;
    pub const @"#root" = &@"#schema";
    pub const @"#type" = &@"#schema".tables[8];
    pub const @"#constructor" = struct {
@"input_bounds_start": f64 = 0, @"input_bounds_end": f64 = 0, @"transform": ?@"ottla".@"AffineTransform1D" = null, };

    @"#ref": flatbuffers.Ref,

    pub fn @"input_bounds_start"(@"#self": @"MappingAffine") f64 {
        return flatbuffers.decodeScalarField(f64, 0, @"#self".@"#ref", 0);
    }

    pub fn @"input_bounds_end"(@"#self": @"MappingAffine") f64 {
        return flatbuffers.decodeScalarField(f64, 1, @"#self".@"#ref", 0);
    }

    pub fn @"transform"(@"#self": @"MappingAffine") ?@"ottla".@"AffineTransform1D" {
        return flatbuffers.decodeStructField(@"ottla".@"AffineTransform1D", 2, @"#self".@"#ref");
    }

};

pub const @"MappingLinear" = struct {
    pub const @"#kind" = flatbuffers.Kind.Table;
    pub const @"#root" = &@"#schema";
    pub const @"#type" = &@"#schema".tables[9];
    pub const @"#constructor" = struct {
@"input_bounds_start": f64 = 0, @"input_bounds_end": f64 = 0, @"knots": ?[]const @"ottla".@"ControlPoint" = null, };

    @"#ref": flatbuffers.Ref,

    pub fn @"input_bounds_start"(@"#self": @"MappingLinear") f64 {
        return flatbuffers.decodeScalarField(f64, 0, @"#self".@"#ref", 0);
    }

    pub fn @"input_bounds_end"(@"#self": @"MappingLinear") f64 {
        return flatbuffers.decodeScalarField(f64, 1, @"#self".@"#ref", 0);
    }

    pub fn @"knots"(@"#self": @"MappingLinear") ?flatbuffers.Vector(@"ottla".@"ControlPoint") {
        return flatbuffers.decodeVectorField(@"ottla".@"ControlPoint", 2, @"#self".@"#ref");
    }

};

pub const @"MappingWrapper" = struct {
    pub const @"#kind" = flatbuffers.Kind.Table;
    pub const @"#root" = &@"#schema";
    pub const @"#type" = &@"#schema".tables[10];
    pub const @"#constructor" = struct {
@"mapping_type": @"ottla".@"MappingType" = @enumFromInt(0), @"affine": ?@"ottla".@"MappingAffine" = null, @"linear": ?@"ottla".@"MappingLinear" = null, };

    @"#ref": flatbuffers.Ref,

    pub fn @"mapping_type"(@"#self": @"MappingWrapper") @"ottla".@"MappingType" {
        return flatbuffers.decodeEnumField(@"ottla".@"MappingType", 0, @"#self".@"#ref", @enumFromInt(0));
    }

    pub fn @"affine"(@"#self": @"MappingWrapper") ?@"ottla".@"MappingAffine" {
        return flatbuffers.decodeTableField(@"ottla".@"MappingAffine", 1, @"#self".@"#ref");
    }

    pub fn @"linear"(@"#self": @"MappingWrapper") ?@"ottla".@"MappingLinear" {
        return flatbuffers.decodeTableField(@"ottla".@"MappingLinear", 2, @"#self".@"#ref");
    }

};

pub const @"MediaReference" = struct {
    pub const @"#kind" = flatbuffers.Kind.Table;
    pub const @"#root" = &@"#schema";
    pub const @"#type" = &@"#schema".tables[11];
    pub const @"#constructor" = struct {
@"data_reference_type": @"ottla".@"MediaDataReference" = .NONE, @"bounds": ?@"ottla".@"Bounds" = null, @"domain": ?@"ottla".@"Domain" = null, @"discrete_partition": ?@"ottla".@"SampleIndexGenerator" = null, @"interpolating": @"ottla".@"MediaInterpolationType" = @enumFromInt(0), };

    @"#ref": flatbuffers.Ref,

    pub fn @"data_reference_type"(@"#self": @"MediaReference") @"ottla".@"MediaDataReference" {
        return flatbuffers.decodeUnionField(@"ottla".@"MediaDataReference", 0, 1, @"#self".@"#ref");
    }

    pub fn @"bounds"(@"#self": @"MediaReference") ?@"ottla".@"Bounds" {
        return flatbuffers.decodeTableField(@"ottla".@"Bounds", 2, @"#self".@"#ref");
    }

    pub fn @"domain"(@"#self": @"MediaReference") ?@"ottla".@"Domain" {
        return flatbuffers.decodeTableField(@"ottla".@"Domain", 3, @"#self".@"#ref");
    }

    pub fn @"discrete_partition"(@"#self": @"MediaReference") ?@"ottla".@"SampleIndexGenerator" {
        return flatbuffers.decodeTableField(@"ottla".@"SampleIndexGenerator", 4, @"#self".@"#ref");
    }

    pub fn @"interpolating"(@"#self": @"MediaReference") @"ottla".@"MediaInterpolationType" {
        return flatbuffers.decodeEnumField(@"ottla".@"MediaInterpolationType", 5, @"#self".@"#ref", @enumFromInt(0));
    }

};

pub const @"MetadataBlock" = struct {
    pub const @"#kind" = flatbuffers.Kind.Table;
    pub const @"#root" = &@"#schema";
    pub const @"#type" = &@"#schema".tables[12];
    pub const @"#constructor" = struct {
@"keys": ?[]const []const u8 = null, @"types": ?[]const i8 = null, @"scalars": ?[]const @"ottla".@"PackedScalar" = null, @"string_values": ?[]const []const u8 = null, @"string_indices": ?[]const u32 = null, @"nested_blocks": ?[]const @"ottla".@"MetadataBlock" = null, @"nested_indices": ?[]const u32 = null, @"array_blocks": ?[]const @"ottla".@"MetadataBlock" = null, @"array_indices": ?[]const u32 = null, };

    @"#ref": flatbuffers.Ref,

    pub fn @"keys"(@"#self": @"MetadataBlock") ?flatbuffers.Vector(flatbuffers.String) {
        return flatbuffers.decodeVectorField(flatbuffers.String, 0, @"#self".@"#ref");
    }

    pub fn @"types"(@"#self": @"MetadataBlock") ?flatbuffers.Vector(i8) {
        return flatbuffers.decodeVectorField(i8, 1, @"#self".@"#ref");
    }

    pub fn @"scalars"(@"#self": @"MetadataBlock") ?flatbuffers.Vector(@"ottla".@"PackedScalar") {
        return flatbuffers.decodeVectorField(@"ottla".@"PackedScalar", 2, @"#self".@"#ref");
    }

    pub fn @"string_values"(@"#self": @"MetadataBlock") ?flatbuffers.Vector(flatbuffers.String) {
        return flatbuffers.decodeVectorField(flatbuffers.String, 3, @"#self".@"#ref");
    }

    pub fn @"string_indices"(@"#self": @"MetadataBlock") ?flatbuffers.Vector(u32) {
        return flatbuffers.decodeVectorField(u32, 4, @"#self".@"#ref");
    }

    pub fn @"nested_blocks"(@"#self": @"MetadataBlock") ?flatbuffers.Vector(@"ottla".@"MetadataBlock") {
        return flatbuffers.decodeVectorField(@"ottla".@"MetadataBlock", 5, @"#self".@"#ref");
    }

    pub fn @"nested_indices"(@"#self": @"MetadataBlock") ?flatbuffers.Vector(u32) {
        return flatbuffers.decodeVectorField(u32, 6, @"#self".@"#ref");
    }

    pub fn @"array_blocks"(@"#self": @"MetadataBlock") ?flatbuffers.Vector(@"ottla".@"MetadataBlock") {
        return flatbuffers.decodeVectorField(@"ottla".@"MetadataBlock", 7, @"#self".@"#ref");
    }

    pub fn @"array_indices"(@"#self": @"MetadataBlock") ?flatbuffers.Vector(u32) {
        return flatbuffers.decodeVectorField(u32, 8, @"#self".@"#ref");
    }

};

pub const @"MetadataMap" = struct {
    pub const @"#kind" = flatbuffers.Kind.Table;
    pub const @"#root" = &@"#schema";
    pub const @"#type" = &@"#schema".tables[13];
    pub const @"#constructor" = struct {
@"hashes": ?[]const []const u8 = null, @"block_offsets": ?[]const u32 = null, @"block_lengths": ?[]const u32 = null, @"all_keys": ?[]const []const u8 = null, @"all_types": ?[]const u8 = null, @"all_scalars": ?[]const @"ottla".@"PackedScalar" = null, @"string_values": ?[]const []const u8 = null, @"string_key_indices": ?[]const u32 = null, @"string_value_indices": ?[]const u32 = null, @"nested_blocks": ?[]const @"ottla".@"MetadataBlock" = null, @"nested_key_indices": ?[]const u32 = null, @"nested_block_indices": ?[]const u32 = null, };

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

    pub fn @"all_scalars"(@"#self": @"MetadataMap") ?flatbuffers.Vector(@"ottla".@"PackedScalar") {
        return flatbuffers.decodeVectorField(@"ottla".@"PackedScalar", 5, @"#self".@"#ref");
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

    pub fn @"nested_blocks"(@"#self": @"MetadataMap") ?flatbuffers.Vector(@"ottla".@"MetadataBlock") {
        return flatbuffers.decodeVectorField(@"ottla".@"MetadataBlock", 9, @"#self".@"#ref");
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
    pub const @"#type" = &@"#schema".tables[14];
    pub const @"#constructor" = struct {
};

    @"#ref": flatbuffers.Ref,

};

pub const @"RationalRate" = struct {
    pub const @"#kind" = flatbuffers.Kind.Table;
    pub const @"#root" = &@"#schema";
    pub const @"#type" = &@"#schema".tables[15];
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
    pub const @"#type" = &@"#schema".tables[16];
    pub const @"#constructor" = struct {
@"sample_rate_hz_type": @"ottla".@"RateSpecifier" = .NONE, @"start_index": u64 = 0, };

    @"#ref": flatbuffers.Ref,

    pub fn @"sample_rate_hz_type"(@"#self": @"SampleIndexGenerator") @"ottla".@"RateSpecifier" {
        return flatbuffers.decodeUnionField(@"ottla".@"RateSpecifier", 0, 1, @"#self".@"#ref");
    }

    pub fn @"start_index"(@"#self": @"SampleIndexGenerator") u64 {
        return flatbuffers.decodeScalarField(u64, 2, @"#self".@"#ref", 0);
    }

};

pub const @"SignalReference" = struct {
    pub const @"#kind" = flatbuffers.Kind.Table;
    pub const @"#root" = &@"#schema";
    pub const @"#type" = &@"#schema".tables[17];
    pub const @"#constructor" = struct {
@"signal_generator_type": @"ottla".@"SignalGenerator" = .NONE, };

    @"#ref": flatbuffers.Ref,

    pub fn @"signal_generator_type"(@"#self": @"SignalReference") @"ottla".@"SignalGenerator" {
        return flatbuffers.decodeUnionField(@"ottla".@"SignalGenerator", 0, 1, @"#self".@"#ref");
    }

};

pub const @"SineSignal" = struct {
    pub const @"#kind" = flatbuffers.Kind.Table;
    pub const @"#root" = &@"#schema";
    pub const @"#type" = &@"#schema".tables[18];
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
    pub const @"#type" = &@"#schema".tables[19];
    pub const @"#constructor" = struct {
@"name": ?[]const u8 = null, @"bounds": ?@"ottla".@"Bounds" = null, @"children": ?[]const @"ottla".@"ComposableWrapper" = null, };

    @"#ref": flatbuffers.Ref,

    pub fn @"name"(@"#self": @"Stack") ?flatbuffers.String {
        return flatbuffers.decodeStringField(0, @"#self".@"#ref");
    }

    pub fn @"bounds"(@"#self": @"Stack") ?@"ottla".@"Bounds" {
        return flatbuffers.decodeTableField(@"ottla".@"Bounds", 1, @"#self".@"#ref");
    }

    pub fn @"children"(@"#self": @"Stack") ?flatbuffers.Vector(@"ottla".@"ComposableWrapper") {
        return flatbuffers.decodeVectorField(@"ottla".@"ComposableWrapper", 2, @"#self".@"#ref");
    }

};

pub const @"Timeline" = struct {
    pub const @"#kind" = flatbuffers.Kind.Table;
    pub const @"#root" = &@"#schema";
    pub const @"#type" = &@"#schema".tables[20];
    pub const @"#constructor" = struct {
@"schema_version": u32 = 1, @"name": ?[]const u8 = null, @"children": ?[]const @"ottla".@"ComposableWrapper" = null, @"presentation_space_discrete_partitions": ?@"ottla".@"DiscretePartitionDomainMap" = null, @"metadata_map": ?@"ottla".@"MetadataMap" = null, };

    @"#ref": flatbuffers.Ref,

    pub fn @"schema_version"(@"#self": @"Timeline") u32 {
        return flatbuffers.decodeScalarField(u32, 0, @"#self".@"#ref", 1);
    }

    pub fn @"name"(@"#self": @"Timeline") ?flatbuffers.String {
        return flatbuffers.decodeStringField(1, @"#self".@"#ref");
    }

    pub fn @"children"(@"#self": @"Timeline") ?flatbuffers.Vector(@"ottla".@"ComposableWrapper") {
        return flatbuffers.decodeVectorField(@"ottla".@"ComposableWrapper", 2, @"#self".@"#ref");
    }

    pub fn @"presentation_space_discrete_partitions"(@"#self": @"Timeline") ?@"ottla".@"DiscretePartitionDomainMap" {
        return flatbuffers.decodeTableField(@"ottla".@"DiscretePartitionDomainMap", 3, @"#self".@"#ref");
    }

    pub fn @"metadata_map"(@"#self": @"Timeline") ?@"ottla".@"MetadataMap" {
        return flatbuffers.decodeTableField(@"ottla".@"MetadataMap", 4, @"#self".@"#ref");
    }

};

pub const @"Topology" = struct {
    pub const @"#kind" = flatbuffers.Kind.Table;
    pub const @"#root" = &@"#schema";
    pub const @"#type" = &@"#schema".tables[21];
    pub const @"#constructor" = struct {
@"mappings": ?[]const @"ottla".@"MappingWrapper" = null, };

    @"#ref": flatbuffers.Ref,

    pub fn @"mappings"(@"#self": @"Topology") ?flatbuffers.Vector(@"ottla".@"MappingWrapper") {
        return flatbuffers.decodeVectorField(@"ottla".@"MappingWrapper", 0, @"#self".@"#ref");
    }

};

pub const @"Track" = struct {
    pub const @"#kind" = flatbuffers.Kind.Table;
    pub const @"#root" = &@"#schema";
    pub const @"#type" = &@"#schema".tables[22];
    pub const @"#constructor" = struct {
@"name": ?[]const u8 = null, @"bounds": ?@"ottla".@"Bounds" = null, @"children": ?[]const @"ottla".@"ComposableWrapper" = null, };

    @"#ref": flatbuffers.Ref,

    pub fn @"name"(@"#self": @"Track") ?flatbuffers.String {
        return flatbuffers.decodeStringField(0, @"#self".@"#ref");
    }

    pub fn @"bounds"(@"#self": @"Track") ?@"ottla".@"Bounds" {
        return flatbuffers.decodeTableField(@"ottla".@"Bounds", 1, @"#self".@"#ref");
    }

    pub fn @"children"(@"#self": @"Track") ?flatbuffers.Vector(@"ottla".@"ComposableWrapper") {
        return flatbuffers.decodeVectorField(@"ottla".@"ComposableWrapper", 2, @"#self".@"#ref");
    }

};

pub const @"Transition" = struct {
    pub const @"#kind" = flatbuffers.Kind.Table;
    pub const @"#root" = &@"#schema";
    pub const @"#type" = &@"#schema".tables[23];
    pub const @"#constructor" = struct {
@"name": ?[]const u8 = null, @"container": ?@"ottla".@"Stack" = null, @"kind": []const u8, @"bounds_start": f64 = 0, @"bounds_end": f64 = 0, @"has_bounds": bool = false, };

    @"#ref": flatbuffers.Ref,

    pub fn @"name"(@"#self": @"Transition") ?flatbuffers.String {
        return flatbuffers.decodeStringField(0, @"#self".@"#ref");
    }

    pub fn @"container"(@"#self": @"Transition") ?@"ottla".@"Stack" {
        return flatbuffers.decodeTableField(@"ottla".@"Stack", 1, @"#self".@"#ref");
    }

    pub fn @"kind"(@"#self": @"Transition") flatbuffers.String {
        return flatbuffers.decodeStringField(2, @"#self".@"#ref") orelse
            @panic("missing ottla.Transition.kind field");
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
    pub const @"#type" = &@"#schema".tables[24];
    pub const @"#constructor" = struct {
@"target_uri": []const u8, };

    @"#ref": flatbuffers.Ref,

    pub fn @"target_uri"(@"#self": @"URIReference") flatbuffers.String {
        return flatbuffers.decodeStringField(0, @"#self".@"#ref") orelse
            @panic("missing ottla.URIReference.target_uri field");
    }

};

pub const @"Warp" = struct {
    pub const @"#kind" = flatbuffers.Kind.Table;
    pub const @"#root" = &@"#schema";
    pub const @"#type" = &@"#schema".tables[25];
    pub const @"#constructor" = struct {
@"name": ?[]const u8 = null, @"child": ?@"ottla".@"ComposableWrapper" = null, @"transform": ?@"ottla".@"Topology" = null, };

    @"#ref": flatbuffers.Ref,

    pub fn @"name"(@"#self": @"Warp") ?flatbuffers.String {
        return flatbuffers.decodeStringField(0, @"#self".@"#ref");
    }

    pub fn @"child"(@"#self": @"Warp") ?@"ottla".@"ComposableWrapper" {
        return flatbuffers.decodeTableField(@"ottla".@"ComposableWrapper", 1, @"#self".@"#ref");
    }

    pub fn @"transform"(@"#self": @"Warp") ?@"ottla".@"Topology" {
        return flatbuffers.decodeTableField(@"ottla".@"Topology", 2, @"#self".@"#ref");
    }

};

};
