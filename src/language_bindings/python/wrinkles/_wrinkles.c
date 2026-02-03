/**
 * Python C extension for wrinkles temporal hierarchy library.
 *
 * This module provides Python bindings for the wrinkles C API,
 * enabling reading OTIO files and performing temporal projections.
 */

#define PY_SSIZE_T_CLEAN
#include <Python.h>
#include "structmember.h"
#include "opentimelineio_c.h"

/* ========== Forward Declarations ========== */
static PyTypeObject WrinklesTimelineType;
static PyTypeObject WrinklesStackType;
static PyTypeObject WrinklesTrackType;
static PyTypeObject WrinklesClipType;
static PyTypeObject WrinklesGapType;
static PyTypeObject WrinklesWarpType;
static PyTypeObject WrinklesTransitionType;
static PyTypeObject WrinklesContinuousIntervalType;
static PyTypeObject WrinklesProjectionOperatorType;

/* ========== ContinuousInterval Type ========== */
typedef struct {
    PyObject_HEAD
    double start;
    double end;
} WrinklesContinuousInterval;

static void ContinuousInterval_dealloc(WrinklesContinuousInterval *self) {
    Py_TYPE(self)->tp_free((PyObject *)self);
}

static PyObject *ContinuousInterval_new(PyTypeObject *type, PyObject *args, PyObject *kwds) {
    WrinklesContinuousInterval *self;
    self = (WrinklesContinuousInterval *)type->tp_alloc(type, 0);
    if (self != NULL) {
        self->start = 0.0;
        self->end = 0.0;
    }
    return (PyObject *)self;
}

static int ContinuousInterval_init(WrinklesContinuousInterval *self, PyObject *args, PyObject *kwds) {
    static char *kwlist[] = {"start", "end", NULL};
    if (!PyArg_ParseTupleAndKeywords(args, kwds, "dd", kwlist, &self->start, &self->end))
        return -1;
    return 0;
}

static PyObject *ContinuousInterval_repr(WrinklesContinuousInterval *self) {
    return PyUnicode_FromFormat("ContinuousInterval(start=%R, end=%R)",
                                PyFloat_FromDouble(self->start),
                                PyFloat_FromDouble(self->end));
}

static PyObject *ContinuousInterval_get_duration(WrinklesContinuousInterval *self, void *closure) {
    return PyFloat_FromDouble(self->end - self->start);
}

static PyMemberDef ContinuousInterval_members[] = {
    {"start", T_DOUBLE, offsetof(WrinklesContinuousInterval, start), 0, "Start time"},
    {"end", T_DOUBLE, offsetof(WrinklesContinuousInterval, end), 0, "End time"},
    {NULL}
};

static PyGetSetDef ContinuousInterval_getsetters[] = {
    {"duration", (getter)ContinuousInterval_get_duration, NULL, "Duration (end - start)", NULL},
    {NULL}
};

static PyTypeObject WrinklesContinuousIntervalType = {
    PyVarObject_HEAD_INIT(NULL, 0)
    .tp_name = "wrinkles.ContinuousInterval",
    .tp_doc = "A continuous time interval with start and end",
    .tp_basicsize = sizeof(WrinklesContinuousInterval),
    .tp_itemsize = 0,
    .tp_flags = Py_TPFLAGS_DEFAULT,
    .tp_new = ContinuousInterval_new,
    .tp_init = (initproc)ContinuousInterval_init,
    .tp_dealloc = (destructor)ContinuousInterval_dealloc,
    .tp_repr = (reprfunc)ContinuousInterval_repr,
    .tp_members = ContinuousInterval_members,
    .tp_getset = ContinuousInterval_getsetters,
};

/* ========== Base CompositionItem Type ========== */
typedef struct {
    PyObject_HEAD
    otio_Arena arena;           /* Arena allocator (only valid for root timeline) */
    otio_CompositionItemHandle handle;
    PyObject *parent;           /* Reference to parent object (for memory safety) */
    int owns_arena;             /* 1 if this object owns the arena */
} WrinklesCompositionItem;

/* Helper to create a Python object from a C handle */
static PyObject *create_composition_item(otio_CompositionItemHandle handle, PyObject *parent, otio_Arena arena, int owns_arena);

static void CompositionItem_dealloc(WrinklesCompositionItem *self) {
    if (self->owns_arena && self->arena.arena != NULL) {
        otio_arena_deinit(self->arena);
    }
    Py_XDECREF(self->parent);
    Py_TYPE(self)->tp_free((PyObject *)self);
}

static PyObject *CompositionItem_get_name(WrinklesCompositionItem *self, void *closure) {
    char buf[1024];
    if (otio_fetch_cvr_name_str(self->handle, buf, sizeof(buf)) < 0) {
        Py_RETURN_NONE;
    }
    if (buf[0] == '\0' || strcmp(buf, "null") == 0) {
        Py_RETURN_NONE;
    }
    return PyUnicode_FromString(buf);
}

static PyObject *CompositionItem_get_type_name(WrinklesCompositionItem *self, void *closure) {
    char buf[64];
    if (otio_fetch_cvr_type_str(self->handle, buf, sizeof(buf)) < 0) {
        return PyUnicode_FromString("unknown");
    }
    return PyUnicode_FromString(buf);
}

static PyObject *CompositionItem_repr(WrinklesCompositionItem *self) {
    char type_buf[64];
    char name_buf[256];

    otio_fetch_cvr_type_str(self->handle, type_buf, sizeof(type_buf));
    otio_fetch_cvr_name_str(self->handle, name_buf, sizeof(name_buf));

    if (name_buf[0] == '\0' || strcmp(name_buf, "null") == 0) {
        return PyUnicode_FromFormat("<%s>", type_buf);
    }
    return PyUnicode_FromFormat("<%s '%s'>", type_buf, name_buf);
}

static Py_ssize_t CompositionItem_length(WrinklesCompositionItem *self) {
    int count = otio_child_count_cvr(self->handle);
    return count >= 0 ? count : 0;
}

static PyObject *CompositionItem_item(WrinklesCompositionItem *self, Py_ssize_t index) {
    int count = otio_child_count_cvr(self->handle);
    if (count < 0 || index < 0 || index >= count) {
        PyErr_SetString(PyExc_IndexError, "index out of range");
        return NULL;
    }

    otio_CompositionItemHandle child = otio_fetch_child_cvr_ind(self->handle, (int)index);
    if (child.kind == otio_ct_err) {
        PyErr_SetString(PyExc_RuntimeError, "Failed to get child");
        return NULL;
    }

    return create_composition_item(child, (PyObject *)self, self->arena, 0);
}

static PySequenceMethods CompositionItem_as_sequence = {
    .sq_length = (lenfunc)CompositionItem_length,
    .sq_item = (ssizeargfunc)CompositionItem_item,
};

/* Iterator for CompositionItem */
typedef struct {
    PyObject_HEAD
    WrinklesCompositionItem *container;
    Py_ssize_t index;
} WrinklesCompositionItemIter;

static void CompositionItemIter_dealloc(WrinklesCompositionItemIter *self) {
    Py_XDECREF(self->container);
    Py_TYPE(self)->tp_free((PyObject *)self);
}

static PyObject *CompositionItemIter_next(WrinklesCompositionItemIter *self) {
    if (self->index >= CompositionItem_length(self->container)) {
        return NULL;  /* StopIteration */
    }
    PyObject *item = CompositionItem_item(self->container, self->index);
    self->index++;
    return item;
}

static PyTypeObject WrinklesCompositionItemIterType = {
    PyVarObject_HEAD_INIT(NULL, 0)
    .tp_name = "wrinkles._CompositionItemIter",
    .tp_basicsize = sizeof(WrinklesCompositionItemIter),
    .tp_flags = Py_TPFLAGS_DEFAULT,
    .tp_dealloc = (destructor)CompositionItemIter_dealloc,
    .tp_iter = PyObject_SelfIter,
    .tp_iternext = (iternextfunc)CompositionItemIter_next,
};

static PyObject *CompositionItem_iter(WrinklesCompositionItem *self) {
    WrinklesCompositionItemIter *iter = PyObject_New(WrinklesCompositionItemIter, &WrinklesCompositionItemIterType);
    if (!iter) return NULL;

    Py_INCREF(self);
    iter->container = self;
    iter->index = 0;
    return (PyObject *)iter;
}

/* Context manager methods */
static PyObject *CompositionItem_enter(WrinklesCompositionItem *self, PyObject *args) {
    Py_INCREF(self);
    return (PyObject *)self;
}

static PyObject *CompositionItem_exit(WrinklesCompositionItem *self, PyObject *args) {
    /* Cleanup is handled by dealloc */
    Py_RETURN_NONE;
}

/* Get discrete info (frame rate, start index) for media space */
static PyObject *CompositionItem_get_discrete_info(WrinklesCompositionItem *self, PyObject *args) {
    int domain = otio_dm_picture;  /* Default to picture domain */
    if (!PyArg_ParseTuple(args, "|i", &domain))
        return NULL;

    otio_DiscreteDatasourceIndexGenerator info;
    int result = otio_fetch_discrete_info(self->handle, otio_sl_media, domain, &info);

    if (result != 0) {
        Py_RETURN_NONE;
    }

    /* Return a dict with rate and start_index */
    double rate = (double)info.sample_rate_hz.num / (double)info.sample_rate_hz.den;
    return Py_BuildValue("{s:d,s:k}", "rate", rate, "start_index", (unsigned long)info.start_index);
}

/* Convert continuous time to discrete frame index */
static PyObject *CompositionItem_continuous_to_discrete(WrinklesCompositionItem *self, PyObject *args) {
    double time;
    int domain = otio_dm_picture;  /* Default to picture domain */
    if (!PyArg_ParseTuple(args, "d|i", &time, &domain))
        return NULL;

    size_t index = otio_fetch_continuous_ordinate_to_discrete_index(
        self->handle, (float)time, otio_sl_media, domain);

    return PyLong_FromSize_t(index);
}

static PyMethodDef CompositionItem_methods[] = {
    {"__enter__", (PyCFunction)CompositionItem_enter, METH_NOARGS, "Enter context manager"},
    {"__exit__", (PyCFunction)CompositionItem_exit, METH_VARARGS, "Exit context manager"},
    {"get_discrete_info", (PyCFunction)CompositionItem_get_discrete_info, METH_VARARGS,
     "Get discrete info (rate, start_index) for media space. Optional domain arg (0=time, 1=picture, 2=audio)"},
    {"continuous_to_discrete", (PyCFunction)CompositionItem_continuous_to_discrete, METH_VARARGS,
     "Convert continuous time to discrete frame index. Args: (time, domain=1)"},
    {NULL}
};

static PyGetSetDef CompositionItem_getsetters[] = {
    {"name", (getter)CompositionItem_get_name, NULL, "Item name", NULL},
    {"type_name", (getter)CompositionItem_get_type_name, NULL, "Item type name", NULL},
    {NULL}
};

/* ========== Timeline Type ========== */
static PyObject *Timeline_get_tracks(WrinklesCompositionItem *self, void *closure) {
    /*
     * In wrinkles, the Timeline directly contains Track children.
     * For API compatibility with OpenTimelineIO, the `tracks` property
     * returns the Timeline itself, which is iterable over its track children.
     */
    Py_INCREF(self);
    return (PyObject *)self;
}

static PyGetSetDef Timeline_getsetters[] = {
    {"name", (getter)CompositionItem_get_name, NULL, "Timeline name", NULL},
    {"type_name", (getter)CompositionItem_get_type_name, NULL, "Item type name", NULL},
    {"tracks", (getter)Timeline_get_tracks, NULL, "Timeline tracks (Stack)", NULL},
    {NULL}
};

static PyTypeObject WrinklesTimelineType = {
    PyVarObject_HEAD_INIT(NULL, 0)
    .tp_name = "wrinkles.Timeline",
    .tp_doc = "Wrinkles Timeline object",
    .tp_basicsize = sizeof(WrinklesCompositionItem),
    .tp_flags = Py_TPFLAGS_DEFAULT,
    .tp_dealloc = (destructor)CompositionItem_dealloc,
    .tp_repr = (reprfunc)CompositionItem_repr,
    .tp_as_sequence = &CompositionItem_as_sequence,
    .tp_iter = (getiterfunc)CompositionItem_iter,
    .tp_methods = CompositionItem_methods,
    .tp_getset = Timeline_getsetters,
};

/* ========== Stack Type ========== */
static PyTypeObject WrinklesStackType = {
    PyVarObject_HEAD_INIT(NULL, 0)
    .tp_name = "wrinkles.Stack",
    .tp_doc = "Wrinkles Stack object (simultaneous container)",
    .tp_basicsize = sizeof(WrinklesCompositionItem),
    .tp_flags = Py_TPFLAGS_DEFAULT,
    .tp_dealloc = (destructor)CompositionItem_dealloc,
    .tp_repr = (reprfunc)CompositionItem_repr,
    .tp_as_sequence = &CompositionItem_as_sequence,
    .tp_iter = (getiterfunc)CompositionItem_iter,
    .tp_methods = CompositionItem_methods,
    .tp_getset = CompositionItem_getsetters,
};

/* ========== Track Type ========== */
static PyTypeObject WrinklesTrackType = {
    PyVarObject_HEAD_INIT(NULL, 0)
    .tp_name = "wrinkles.Track",
    .tp_doc = "Wrinkles Track object (sequential container)",
    .tp_basicsize = sizeof(WrinklesCompositionItem),
    .tp_flags = Py_TPFLAGS_DEFAULT,
    .tp_dealloc = (destructor)CompositionItem_dealloc,
    .tp_repr = (reprfunc)CompositionItem_repr,
    .tp_as_sequence = &CompositionItem_as_sequence,
    .tp_iter = (getiterfunc)CompositionItem_iter,
    .tp_methods = CompositionItem_methods,
    .tp_getset = CompositionItem_getsetters,
};

/* ========== Clip Type ========== */
static PyTypeObject WrinklesClipType = {
    PyVarObject_HEAD_INIT(NULL, 0)
    .tp_name = "wrinkles.Clip",
    .tp_doc = "Wrinkles Clip object",
    .tp_basicsize = sizeof(WrinklesCompositionItem),
    .tp_flags = Py_TPFLAGS_DEFAULT,
    .tp_dealloc = (destructor)CompositionItem_dealloc,
    .tp_repr = (reprfunc)CompositionItem_repr,
    .tp_methods = CompositionItem_methods,
    .tp_getset = CompositionItem_getsetters,
};

/* ========== Gap Type ========== */
static PyTypeObject WrinklesGapType = {
    PyVarObject_HEAD_INIT(NULL, 0)
    .tp_name = "wrinkles.Gap",
    .tp_doc = "Wrinkles Gap object",
    .tp_basicsize = sizeof(WrinklesCompositionItem),
    .tp_flags = Py_TPFLAGS_DEFAULT,
    .tp_dealloc = (destructor)CompositionItem_dealloc,
    .tp_repr = (reprfunc)CompositionItem_repr,
    .tp_methods = CompositionItem_methods,
    .tp_getset = CompositionItem_getsetters,
};

/* ========== Warp Type ========== */
static PyTypeObject WrinklesWarpType = {
    PyVarObject_HEAD_INIT(NULL, 0)
    .tp_name = "wrinkles.Warp",
    .tp_doc = "Wrinkles Warp object (time warp)",
    .tp_basicsize = sizeof(WrinklesCompositionItem),
    .tp_flags = Py_TPFLAGS_DEFAULT,
    .tp_dealloc = (destructor)CompositionItem_dealloc,
    .tp_repr = (reprfunc)CompositionItem_repr,
    .tp_as_sequence = &CompositionItem_as_sequence,
    .tp_iter = (getiterfunc)CompositionItem_iter,
    .tp_methods = CompositionItem_methods,
    .tp_getset = CompositionItem_getsetters,
};

/* ========== Transition Type ========== */
static PyTypeObject WrinklesTransitionType = {
    PyVarObject_HEAD_INIT(NULL, 0)
    .tp_name = "wrinkles.Transition",
    .tp_doc = "Wrinkles Transition object",
    .tp_basicsize = sizeof(WrinklesCompositionItem),
    .tp_flags = Py_TPFLAGS_DEFAULT,
    .tp_dealloc = (destructor)CompositionItem_dealloc,
    .tp_repr = (reprfunc)CompositionItem_repr,
    .tp_methods = CompositionItem_methods,
    .tp_getset = CompositionItem_getsetters,
};

/* ========== ProjectionOperator Type ========== */
typedef struct {
    PyObject_HEAD
    otio_Arena arena;
    otio_ProjectionOperator po;
    PyObject *timeline;  /* Reference to keep timeline alive */
} WrinklesProjectionOperator;

static void ProjectionOperator_dealloc(WrinklesProjectionOperator *self) {
    Py_XDECREF(self->timeline);
    /* Note: po is allocated in the arena, cleaned up with timeline */
    Py_TYPE(self)->tp_free((PyObject *)self);
}

static PyObject *ProjectionOperator_project_cc(WrinklesProjectionOperator *self, PyObject *args) {
    double input;
    if (!PyArg_ParseTuple(args, "d", &input))
        return NULL;

    double output;
    int result = otio_po_project_ordinate_cc(self->po, input, &output);

    if (result < 0) {
        PyErr_SetString(PyExc_RuntimeError, "Projection failed");
        return NULL;
    }
    if (result == 1) {
        /* Out of bounds */
        Py_RETURN_NONE;
    }

    return PyFloat_FromDouble(output);
}

static PyObject *ProjectionOperator_project_range_cc(WrinklesProjectionOperator *self, PyObject *args) {
    double input_start, input_end;
    if (!PyArg_ParseTuple(args, "dd", &input_start, &input_end))
        return NULL;

    double output_start, output_end;
    int result = otio_po_project_range_cc(
        self->arena.allocator,
        self->po,
        input_start,
        input_end,
        &output_start,
        &output_end
    );

    if (result != 0) {
        PyErr_SetString(PyExc_RuntimeError, "Range projection failed");
        return NULL;
    }

    /* Return a ContinuousInterval */
    WrinklesContinuousInterval *interval = PyObject_New(WrinklesContinuousInterval, &WrinklesContinuousIntervalType);
    if (!interval) return NULL;

    interval->start = output_start;
    interval->end = output_end;
    return (PyObject *)interval;
}

static PyObject *ProjectionOperator_get_source(WrinklesProjectionOperator *self, void *closure) {
    otio_CompositionItemHandle source = otio_po_fetch_source(self->po);
    if (source.kind == otio_ct_err) {
        Py_RETURN_NONE;
    }
    return create_composition_item(source, self->timeline, ((WrinklesCompositionItem *)self->timeline)->arena, 0);
}

static PyObject *ProjectionOperator_get_destination(WrinklesProjectionOperator *self, void *closure) {
    otio_CompositionItemHandle dest = otio_po_fetch_destination(self->po);
    if (dest.kind == otio_ct_err) {
        Py_RETURN_NONE;
    }
    return create_composition_item(dest, self->timeline, ((WrinklesCompositionItem *)self->timeline)->arena, 0);
}

static PyMethodDef ProjectionOperator_methods[] = {
    {"project_cc", (PyCFunction)ProjectionOperator_project_cc, METH_VARARGS,
     "Project a continuous ordinate to continuous result"},
    {"project_range_cc", (PyCFunction)ProjectionOperator_project_range_cc, METH_VARARGS,
     "Project a continuous range to continuous result"},
    {NULL}
};

static PyGetSetDef ProjectionOperator_getsetters[] = {
    {"source", (getter)ProjectionOperator_get_source, NULL, "Source composition item", NULL},
    {"destination", (getter)ProjectionOperator_get_destination, NULL, "Destination composition item", NULL},
    {NULL}
};

static PyTypeObject WrinklesProjectionOperatorType = {
    PyVarObject_HEAD_INIT(NULL, 0)
    .tp_name = "wrinkles.ProjectionOperator",
    .tp_doc = "Wrinkles ProjectionOperator for temporal projections",
    .tp_basicsize = sizeof(WrinklesProjectionOperator),
    .tp_flags = Py_TPFLAGS_DEFAULT,
    .tp_dealloc = (destructor)ProjectionOperator_dealloc,
    .tp_methods = ProjectionOperator_methods,
    .tp_getset = ProjectionOperator_getsetters,
};

/* ========== Helper Functions ========== */
static PyObject *create_composition_item(otio_CompositionItemHandle handle, PyObject *parent, otio_Arena arena, int owns_arena) {
    PyTypeObject *type;
    switch (handle.kind) {
        case otio_ct_timeline:
            type = &WrinklesTimelineType;
            break;
        case otio_ct_stack:
            type = &WrinklesStackType;
            break;
        case otio_ct_track:
            type = &WrinklesTrackType;
            break;
        case otio_ct_clip:
            type = &WrinklesClipType;
            break;
        case otio_ct_gap:
            type = &WrinklesGapType;
            break;
        case otio_ct_warp:
            type = &WrinklesWarpType;
            break;
        case otio_ct_transition:
            type = &WrinklesTransitionType;
            break;
        default:
            PyErr_SetString(PyExc_RuntimeError, "Unknown composition item type");
            return NULL;
    }

    WrinklesCompositionItem *obj = PyObject_New(WrinklesCompositionItem, type);
    if (!obj) return NULL;

    obj->handle = handle;
    obj->arena = arena;
    obj->owns_arena = owns_arena;

    if (parent) {
        Py_INCREF(parent);
        obj->parent = parent;
    } else {
        obj->parent = NULL;
    }

    return (PyObject *)obj;
}

/* ========== Module Functions ========== */
static PyObject *wrinkles_read_from_file(PyObject *self, PyObject *args) {
    const char *filepath;
    if (!PyArg_ParseTuple(args, "s", &filepath))
        return NULL;

    /* Create a new arena for this timeline */
    otio_Arena arena = otio_fetch_allocator_new_arena();
    if (arena.arena == NULL) {
        PyErr_SetString(PyExc_MemoryError, "Failed to create arena allocator");
        return NULL;
    }

    /* Read the file */
    otio_CompositionItemHandle tl = otio_read_from_file(arena.allocator, filepath);
    if (tl.kind == otio_ct_err) {
        otio_arena_deinit(arena);
        PyErr_Format(PyExc_IOError, "Failed to read file: %s", filepath);
        return NULL;
    }

    return create_composition_item(tl, NULL, arena, 1);
}

static PyObject *wrinkles_write_to_file(PyObject *self, PyObject *args) {
    PyObject *timeline_obj;
    const char *filepath;

    if (!PyArg_ParseTuple(args, "O!s", &WrinklesTimelineType, &timeline_obj, &filepath))
        return NULL;

    WrinklesCompositionItem *timeline = (WrinklesCompositionItem *)timeline_obj;

    /* Write the file using the C API */
    int result = otio_write_to_file(timeline->arena.allocator, timeline->handle, filepath);
    if (result != 0) {
        PyErr_Format(PyExc_IOError, "Failed to write file: %s", filepath);
        return NULL;
    }

    Py_RETURN_NONE;
}

static PyObject *wrinkles_build_projection_map(PyObject *self, PyObject *args) {
    PyObject *timeline_obj;
    if (!PyArg_ParseTuple(args, "O!", &WrinklesTimelineType, &timeline_obj))
        return NULL;

    WrinklesCompositionItem *timeline = (WrinklesCompositionItem *)timeline_obj;

    otio_ProjectionTopology po_map = otio_build_projection_op_map_to_media_tp_cvr(
        timeline->arena.allocator,
        timeline->handle
    );

    if (po_map.ref == NULL) {
        PyErr_SetString(PyExc_RuntimeError, "Failed to build projection map");
        return NULL;
    }

    size_t num_endpoints = otio_po_map_fetch_num_endpoints(po_map);

    PyObject *result = PyList_New(0);
    if (!result) return NULL;

    for (size_t seg = 0; seg + 1 < num_endpoints; seg++) {
        size_t num_ops = otio_po_map_fetch_num_operators_for_segment(po_map, seg);

        for (size_t op_idx = 0; op_idx < num_ops; op_idx++) {
            otio_ProjectionOperator po;
            if (otio_po_map_fetch_op(timeline->arena.allocator, po_map, seg, op_idx, &po) != 0) {
                continue;
            }

            WrinklesProjectionOperator *po_obj = PyObject_New(WrinklesProjectionOperator, &WrinklesProjectionOperatorType);
            if (!po_obj) {
                Py_DECREF(result);
                return NULL;
            }

            po_obj->arena = timeline->arena;
            po_obj->po = po;
            Py_INCREF(timeline_obj);
            po_obj->timeline = timeline_obj;

            PyList_Append(result, (PyObject *)po_obj);
            Py_DECREF(po_obj);
        }
    }

    return result;
}

static PyMethodDef wrinkles_methods[] = {
    {
        "read_from_file",
        wrinkles_read_from_file,
        METH_VARARGS,
        "Read a timeline from an OTIO/TLA/TLB file",
    },
    {
        "write_to_file",
        wrinkles_write_to_file,
        METH_VARARGS,
        "Write a timeline to a TLA/TLB/TLZ file. Format is auto-detected from"
            " extension.",
    },
    {
        "build_projection_map",
        wrinkles_build_projection_map,
        METH_VARARGS,
        "Build a projection operator map from a timeline",
    },
    {NULL, NULL, 0, NULL}
};

/* ========== Module Definition ========== */
static struct PyModuleDef wrinkles_module = {
    PyModuleDef_HEAD_INIT,
    .m_name = "_wrinkles",
    .m_doc = "Wrinkles temporal hierarchy library",
    .m_size = -1,
    .m_methods = wrinkles_methods,
};

PyMODINIT_FUNC PyInit__wrinkles(void) {
    /* Initialize types */
    if (PyType_Ready(&WrinklesContinuousIntervalType) < 0)
        return NULL;
    if (PyType_Ready(&WrinklesCompositionItemIterType) < 0)
        return NULL;
    if (PyType_Ready(&WrinklesTimelineType) < 0)
        return NULL;
    if (PyType_Ready(&WrinklesStackType) < 0)
        return NULL;
    if (PyType_Ready(&WrinklesTrackType) < 0)
        return NULL;
    if (PyType_Ready(&WrinklesClipType) < 0)
        return NULL;
    if (PyType_Ready(&WrinklesGapType) < 0)
        return NULL;
    if (PyType_Ready(&WrinklesWarpType) < 0)
        return NULL;
    if (PyType_Ready(&WrinklesTransitionType) < 0)
        return NULL;
    if (PyType_Ready(&WrinklesProjectionOperatorType) < 0)
        return NULL;

    PyObject *m = PyModule_Create(&wrinkles_module);
    if (!m) return NULL;

    /* Add types to module */
    Py_INCREF(&WrinklesContinuousIntervalType);
    if (PyModule_AddObject(m, "ContinuousInterval", (PyObject *)&WrinklesContinuousIntervalType) < 0) {
        Py_DECREF(&WrinklesContinuousIntervalType);
        Py_DECREF(m);
        return NULL;
    }

    Py_INCREF(&WrinklesTimelineType);
    if (PyModule_AddObject(m, "Timeline", (PyObject *)&WrinklesTimelineType) < 0) {
        Py_DECREF(&WrinklesTimelineType);
        Py_DECREF(m);
        return NULL;
    }

    Py_INCREF(&WrinklesStackType);
    if (PyModule_AddObject(m, "Stack", (PyObject *)&WrinklesStackType) < 0) {
        Py_DECREF(&WrinklesStackType);
        Py_DECREF(m);
        return NULL;
    }

    Py_INCREF(&WrinklesTrackType);
    if (PyModule_AddObject(m, "Track", (PyObject *)&WrinklesTrackType) < 0) {
        Py_DECREF(&WrinklesTrackType);
        Py_DECREF(m);
        return NULL;
    }

    Py_INCREF(&WrinklesClipType);
    if (PyModule_AddObject(m, "Clip", (PyObject *)&WrinklesClipType) < 0) {
        Py_DECREF(&WrinklesClipType);
        Py_DECREF(m);
        return NULL;
    }

    Py_INCREF(&WrinklesGapType);
    if (PyModule_AddObject(m, "Gap", (PyObject *)&WrinklesGapType) < 0) {
        Py_DECREF(&WrinklesGapType);
        Py_DECREF(m);
        return NULL;
    }

    Py_INCREF(&WrinklesWarpType);
    if (PyModule_AddObject(m, "Warp", (PyObject *)&WrinklesWarpType) < 0) {
        Py_DECREF(&WrinklesWarpType);
        Py_DECREF(m);
        return NULL;
    }

    Py_INCREF(&WrinklesTransitionType);
    if (PyModule_AddObject(m, "Transition", (PyObject *)&WrinklesTransitionType) < 0) {
        Py_DECREF(&WrinklesTransitionType);
        Py_DECREF(m);
        return NULL;
    }

    Py_INCREF(&WrinklesProjectionOperatorType);
    if (PyModule_AddObject(m, "ProjectionOperator", (PyObject *)&WrinklesProjectionOperatorType) < 0) {
        Py_DECREF(&WrinklesProjectionOperatorType);
        Py_DECREF(m);
        return NULL;
    }

    /* Add domain constants */
    PyModule_AddIntConstant(m, "DOMAIN_TIME", otio_dm_time);
    PyModule_AddIntConstant(m, "DOMAIN_PICTURE", otio_dm_picture);
    PyModule_AddIntConstant(m, "DOMAIN_AUDIO", otio_dm_audio);
    PyModule_AddIntConstant(m, "DOMAIN_METADATA", otio_dm_metadata);

    return m;
}
