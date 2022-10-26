#!/usr/bin/env python

import argparse
import json

import dearpygui.dearpygui as dpg
import dearpygui.demo as demo


"""Parametric Curve IO Curve Viewer/Editor"""


CURVE_POINTS = 1000
CURVE_INC = 1.0/CURVE_POINTS


def demo_func():
    print("open demo")
    demo.show_demo()


def _parse_args():
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.ArgumentDefaultsHelpFormatter
    )
    parser.add_argument(
        'filepath',
        type=str,
        nargs='*',
        default=[],
        help='Curve files to open'
    )
    return parser.parse_args()


def _open_curve(fp):
    with open(fp, 'r') as fi:
        return {"filepath": fp, "data": json.load(fi)}


def main():
    args = _parse_args()

    curves = []
    for fp in args.filepath:
        curves.append(_open_curve(fp))

    knot_positions = knot_positions_from(curves)
    curve_positions = []
    for c in knot_positions:
        # curves
        curve_positions.append([])
        for s in c:
            # segment
            curve_positions[-1].append([])

            # t and v lists
            curve_positions[-1][-1].append([])
            curve_positions[-1][-1].append([])
            for _ in range(CURVE_POINTS+1):
                curve_positions[-1][-1][0].append(0)
                curve_positions[-1][-1][1].append(0)

    computed_curve_positions(knot_positions, curve_positions)

    dpg.create_context()
    dpg.create_viewport(title="Parameteric Curve IO Curve Editor")
    dpg.setup_dearpygui()

    print("building")
    curve_editor_ui(curves, knot_positions, curve_positions)

    dpg.set_primary_window("Curve Editor", True)
    dpg.show_viewport()

    while dpg.is_dearpygui_running():
        computed_curve_positions(knot_positions, curve_positions)
        for c_i, c in enumerate(curve_positions):
            for s_i, s in enumerate(c):
                tag = f"curve_{c_i}_segment_{s_i}"
                dpg.set_value(tag, s)
        dpg.render_dearpygui_frame()

    dpg.destroy_context()


def _lerp_cp(u, a, b):
    return (
        a[0] * (1 - u) + b[0] * u,
        a[1] * (1 - u) + b[1] * u,
    )


def _segment_reduce4(u: float, seg: [[float, float]]) -> [[float, float]]:
    return [
        _lerp_cp(u, seg[0], seg[1]),
        _lerp_cp(u, seg[1], seg[2]),
        _lerp_cp(u, seg[2], seg[3]),
    ]


def _segment_reduce3(u: float, seg: [[float, float]]) -> [[float, float]]:
    return [
        _lerp_cp(u, seg[0], seg[1]),
        _lerp_cp(u, seg[1], seg[2]),
    ]


def _segment_reduce2(u: float, seg: [[float, float]]) -> [[float, float]]:
    return [
        _lerp_cp(u, seg[0], seg[1]),
    ]


def _eval_curve_at(unorm, segment):
    seg4 = [p[1] for p in segment]
    seg3 = _segment_reduce4(unorm, seg4)
    seg2 = _segment_reduce3(unorm, seg3)
    result = _segment_reduce2(unorm, seg2)
    return result[0]


def _find_u(x, pts):
    offset_u = x - pts[0]
    offset_1 = pts[1] - pts[0]
    offset_2 = pts[2] - pts[0]
    offset_3 = pts[3] - pts[0]
    return _find_u_dist(offset_u, offset_1, offset_2, offset_3)


def _bezier0(unorm, p2, p3, p4):
    p1 = 0.0
    z = unorm
    z2 = z*z
    z3 = z2*z

    zmo = z-1.0
    zmo2 = zmo*zmo
    zmo3 = zmo2*zmo

    return (
        (p4 * z3)
        - (p3 * (3.0*z2*zmo))
        + (p2 * (3.0*z*zmo2))
        - (p1 * zmo3)
    )


def _find_u_dist(x, p1, p2, p3):
    MAX_ABS_ERROR = 0.000001
    MAX_ITERATIONS = 45

    if x <= 0:
        return 0

    if x >= p3:
        return 1

    _u1 = 0
    _u2 = 0
    x1 = -x
    x2 = p3 - x

    _u3 = 1.0 - x2 / (x2 - x1)
    x3 = _bezier0(_u3, p1, p2, p3) - x

    if (x3 == 0):
        return _u3

    if (x3 < 0):
        if (1.0 - _u3 <= MAX_ABS_ERROR):
            if (x2 < -x3):
                return 1.0
            return _u3

        _u1 = 1.0
        x1 = x2
    else:
        _u1 = 0.0
        x1 = x1 * x2 / (x2 + x3)

        if (_u3 <= MAX_ABS_ERROR):
            if (-x1 < x3):
                return 0.0
            return _u3

    _u2 = _u3
    x2 = x3

    i = MAX_ITERATIONS - 1

    while (i > 0):
        i -= 1
        _u3 = _u2 - x2 * ((_u2 - _u1) / (x2 - x1))
        x3 = _bezier0(_u3, p1, p2, p3) - x

        if (x3 == 0):
            return _u3

        if (x2 * x3 <= 0):
            _u1 = _u2
            x1 = x2
        else:
            x1 = x1 * x2 / (x2 + x3)

        _u2 = _u3
        x2 = x3

        if (_u2 > _u1):
            if (_u2 - _u1 <= MAX_ABS_ERROR):
                break
        else:
            if (_u1 - _u2 <= MAX_ABS_ERROR):
                break

    if (x1 < 0):
        x1 = -x1
    if (x2 < 0):
        x2 = -x2

    if (x1 < x2):
        return _u1
    return _u2


def _eval_curve_at_x(x, seg):
    return _eval_curve_at(_find_u(x, [p[1][0] for p in seg]), seg)


def knot_positions_from(curves):
    points = []
    for c in curves:
        crv = []
        # import ipdb; ipdb.set_trace()
        for seg_index, seg in enumerate(c["data"]["segments"]):
            s = []
            for p_name, p_value in sorted(seg.items()):
                s.append([p_name, (p_value["time"], p_value["value"])])
            crv.append(s)
        points.append(crv)

    return points


def computed_curve_positions(knot_positions, curve_positions):
    for i, c in enumerate(knot_positions):
        for s_i, s in enumerate(c):
            start_t = s[0][1][0]
            end_t = s[-1][1][0]
            t = start_t
            t_inc = (end_t - start_t)/CURVE_POINTS
            count = 0
            seg = curve_positions[i][s_i]
            while t < end_t:
                new_p = _eval_curve_at_x(t, s)
                try:
                    seg[0][count] = new_p[0]
                    seg[1][count] = new_p[1]
                except Exception as err:
                    import ipdb; ipdb.set_trace()

                t += t_inc
                count += 1


def curve_editor_ui(curves, points, series_data_per_curve):
    width = dpg.get_viewport_width()

    with dpg.window(tag="Curve Editor"):
        with dpg.menu_bar():
            with dpg.menu(label="File"):
                dpg.add_menu_item(label="Open Curve")
                # @TODO: "save" button
                # @TODO: "quit" button
                # @TODO: "diff" button?
            with dpg.menu(label="Debug"):
                dpg.add_menu_item(label="Show Demo", callback=demo.show_demo)
        with dpg.group(horizontal=True):
            with dpg.child_window(width=0.3*width):
                with dpg.collapsing_header(label="Curves", default_open=True):
                    for c_i, c in enumerate(points):
                        base_crv = curves[c_i]
                        with dpg.collapsing_header(
                                label=base_crv["filepath"],
                                default_open=True
                        ):
                            for seg_index, seg in enumerate(points[c_i]):
                                with dpg.collapsing_header(
                                        label=f"Segment {seg_index}",
                                        default_open=True,
                                ):
                                    for p in seg:
                                        with dpg.group(horizontal=True):
                                            p.append(
                                                dpg.add_input_floatx(
                                                    label=f"{c_i}.{seg_index}.{p[0]}",
                                                    default_value=p[1],
                                                    size=2,
                                                ),
                                            )

                            with dpg.collapsing_header(label="Raw JSON"):
                                dpg.add_text(
                                    json.dumps(
                                        base_crv["data"],
                                        sort_keys=True,
                                        indent=4
                                    )
                                )

            with dpg.child_window():
                with dpg.plot(label="Curve Editor", height=-1, width=-1) as p:
                    dpg.add_plot_legend()

                    dpg.add_plot_axis(dpg.mvXAxis, label="input parameter")
                    dpg.add_plot_axis(
                        dpg.mvYAxis,
                        label="output value",
                        tag="y_axis"
                    )

                    for s_i, s in enumerate(c):
                        tag = f"curve_{c_i}_segment_{s_i}"
                        if dpg.does_item_exist(tag):
                            dpg.delete_item(tag)

                        if (
                                s_i >= len(series_data_per_curve[c_i])
                                or c_i >= len(series_data_per_curve)
                        ):
                            import ipdb; ipdb.set_trace()

                        dpg.add_line_series(
                            series_data_per_curve[c_i][s_i][0],
                            series_data_per_curve[c_i][s_i][1],
                            label=f"Curve {c_i} Segment {s_i}",
                            parent="y_axis",
                            tag=tag,
                        )
                        for i, (label, (p_t, p_v), (w_t)) in enumerate(s):
                            def update_point(sender, app_data, user_data):
                                value = dpg.get_value(sender)
                                widget = user_data[0]
                                p_index = user_data[1]
                                seg = user_data[2]
                                s_i = user_data[3]
                                seg[p_index][1] = (value[0], value[1])
                                print(f"{points[0][s_i][p_index]}")
                                dpg.set_value(widget, (value[0], value[1]))

                            w = dpg.add_drag_point(
                                label=label,
                                default_value=(p_t, p_v),
                                callback=update_point,
                            )
                            dpg.set_item_user_data(w, [w_t, i, s, s_i])


if __name__ == "__main__":
    main()
