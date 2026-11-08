// katsa_box2d / shape: shapes and the distance between two shapes.
//
// Ownership: a shape made here belongs to Lua and is freed with kb2_shape_free. Box2D copies the
// shape into a fixture (kb2_fixture_new), so a fixture's shape (kb2_fixture_shape) is a different
// object owned by Box2D; Lua must never free that one.
#include "bridge.h"

#include <vector>

namespace {

// Lua passes points as a flat array { x1, y1, x2, y2, ... }.
std::vector<b2Vec2> toPoints(const float* xy, int count) {
    std::vector<b2Vec2> points(count);
    for (int i = 0; i < count; i++) {
        points[i].Set(xy[i * 2], xy[i * 2 + 1]);
    }
    return points;
}

// Writes up to `max` vertices as { x, y, ... }. Returns how many were written.
int writePoints(float* out, const b2Vec2* vertices, int count, int max) {
    int written = 0;
    for (; written < count && written < max; written++) {
        out[written * 2] = vertices[written].x;
        out[written * 2 + 1] = vertices[written].y;
    }
    return written;
}

} // namespace

// ---------------------------------------------------------------------------------------------
// Construction (coordinates are local to the body the shape will be attached to)
// ---------------------------------------------------------------------------------------------

KB2_EXPORT void* kb2_shape_circle(float x, float y, float radius) {
    b2CircleShape* shape = new b2CircleShape();
    shape->m_p.Set(x, y);
    shape->m_radius = radius;
    return shape;
}

// A convex polygon of 3..b2_maxPolygonVertices (8) points; returns null otherwise. Box2D computes
// the convex hull of the points.
KB2_EXPORT void* kb2_shape_polygon(const float* xy, int count) {
    if (count < 3 || count > b2_maxPolygonVertices) {
        return nullptr;
    }
    std::vector<b2Vec2> points = toPoints(xy, count);
    b2PolygonShape* shape = new b2PolygonShape();
    shape->Set(points.data(), count);
    return shape;
}

// A rectangle with half sizes (hx, hy), centered at (cx, cy) and rotated by `angle`.
KB2_EXPORT void* kb2_shape_box(float hx, float hy, float cx, float cy, float angle) {
    b2PolygonShape* shape = new b2PolygonShape();
    shape->SetAsBox(hx, hy, b2Vec2(cx, cy), angle);
    return shape;
}

KB2_EXPORT void* kb2_shape_edge(float x1, float y1, float x2, float y2) {
    b2EdgeShape* shape = new b2EdgeShape();
    shape->Set(b2Vec2(x1, y1), b2Vec2(x2, y2));
    return shape;
}

// A chain of edges through the points; with `loop` the last point connects to the first.
KB2_EXPORT void* kb2_shape_chain(const float* xy, int count, int loop) {
    std::vector<b2Vec2> points = toPoints(xy, count);
    b2ChainShape* shape = new b2ChainShape();
    if (loop) {
        shape->CreateLoop(points.data(), count);
    } else {
        shape->CreateChain(points.data(), count);
    }
    return shape;
}

KB2_EXPORT void kb2_shape_free(void* shape) {
    delete asShape(shape); // b2Shape has a virtual destructor
}

// ---------------------------------------------------------------------------------------------
// Properties
// ---------------------------------------------------------------------------------------------

// Returns a ShapeTypeCode.
KB2_EXPORT int kb2_shape_type(void* shape) {
    switch (asShape(shape)->GetType()) {
    case b2Shape::e_circle:
        return SHAPE_CIRCLE;
    case b2Shape::e_edge:
        return SHAPE_EDGE;
    case b2Shape::e_polygon:
        return SHAPE_POLYGON;
    default:
        return SHAPE_CHAIN;
    }
}

// The circle radius; for polygons and edges the "skin" radius Box2D keeps around them.
KB2_EXPORT float kb2_shape_radius(void* shape) {
    return asShape(shape)->m_radius;
}

KB2_EXPORT void kb2_shape_set_radius(void* shape, float radius) {
    asShape(shape)->m_radius = radius;
}

// Chains have one child per edge; every other shape has one.
KB2_EXPORT int kb2_shape_child_count(void* shape) {
    return asShape(shape)->GetChildCount();
}

// The points of the shape as { x, y, ... }. Returns the number of points:
//   circle   1 (its center; `max` is not checked, `out` needs 2 floats)
//   edge     2 (`max` is not checked, `out` needs 4 floats)
//   polygon, chain   up to `max`
KB2_EXPORT int kb2_shape_points(void* shape, float* out, int max) {
    b2Shape* s = asShape(shape);
    switch (s->GetType()) {
    case b2Shape::e_circle:
        writeVec(out, static_cast<b2CircleShape*>(s)->m_p);
        return 1;
    case b2Shape::e_edge: {
        b2EdgeShape* edge = static_cast<b2EdgeShape*>(s);
        writeVec(out, edge->m_vertex1);
        writeVec(out + 2, edge->m_vertex2);
        return 2;
    }
    case b2Shape::e_polygon: {
        b2PolygonShape* polygon = static_cast<b2PolygonShape*>(s);
        return writePoints(out, polygon->m_vertices, polygon->m_count, max);
    }
    default: {
        b2ChainShape* chain = static_cast<b2ChainShape*>(s);
        return writePoints(out, chain->m_vertices, chain->m_count, max);
    }
    }
}

// ---------------------------------------------------------------------------------------------
// Geometry queries on a shape placed at (x, y) rotated by `angle`
// ---------------------------------------------------------------------------------------------

KB2_EXPORT int kb2_shape_test_point(void* shape, float x, float y, float angle, float px,
                                    float py) {
    return asShape(shape)->TestPoint(makeTransform(x, y, angle), b2Vec2(px, py));
}

// Casts (x1, y1) -> (x2, y2) against one child. On a hit writes { nx, ny, fraction } and
// returns 1.
KB2_EXPORT int kb2_shape_raycast(void* shape, float x1, float y1, float x2, float y2,
                                 float maxFraction, float x, float y, float angle, int child,
                                 float* out) {
    b2RayCastOutput hit;
    b2RayCastInput ray = makeRay(x1, y1, x2, y2, maxFraction);
    if (!asShape(shape)->RayCast(&hit, ray, makeTransform(x, y, angle), child)) {
        return 0;
    }
    writeRayHit(out, hit);
    return 1;
}

KB2_EXPORT void kb2_shape_aabb(void* shape, float x, float y, float angle, int child,
                               float* out) {
    b2AABB box;
    asShape(shape)->ComputeAABB(&box, makeTransform(x, y, angle), child);
    writeBox(out, box);
}

// Mass of the shape at `density` (kg/m^2): { center.x, center.y, mass, inertia }.
KB2_EXPORT void kb2_shape_mass(void* shape, float density, float* out) {
    b2MassData mass;
    asShape(shape)->ComputeMass(&mass, density);
    writeMass(out, mass);
}

// Closest distance between child `childA` of shape A and child `childB` of shape B, each placed
// by its own transform. Radii are included, so touching circles return 0.
KB2_EXPORT float kb2_distance(void* shapeA, int childA, float ax, float ay, float angleA,
                              void* shapeB, int childB, float bx, float by, float angleB) {
    b2DistanceInput input;
    input.proxyA.Set(asShape(shapeA), childA);
    input.proxyB.Set(asShape(shapeB), childB);
    input.transformA = makeTransform(ax, ay, angleA);
    input.transformB = makeTransform(bx, by, angleB);
    input.useRadii = true;
    b2SimplexCache cache;
    cache.count = 0; // no warm start
    b2DistanceOutput output;
    b2Distance(&output, &cache, &input);
    return output.distance;
}
