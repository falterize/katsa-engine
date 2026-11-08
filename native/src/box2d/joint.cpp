// katsa_box2d / joint: creating joints and reading or changing their properties.
//
// Anchors are given in world coordinates and converted to each body's local frame here, so a
// joint keeps the bodies at their current relative placement. Every creator returns the new
// b2Joint* and must not be called while the world is locked.
#include "bridge.h"

namespace {

void setBodies(b2JointDef& definition, void* bodyA, void* bodyB, int collideConnected) {
    definition.bodyA = asBody(bodyA);
    definition.bodyB = asBody(bodyB);
    definition.collideConnected = collideConnected != 0;
}

// World anchor (x, y) as a point local to `body`.
b2Vec2 localAnchor(void* body, float x, float y) {
    return asBody(body)->GetLocalPoint(b2Vec2(x, y));
}

// World axis (x, y), normalized, as a direction local to `body`.
b2Vec2 localAxis(void* body, float x, float y) {
    b2Vec2 axis(x, y);
    axis.Normalize();
    return asBody(body)->GetLocalVector(axis);
}

b2Joint* create(void* world, const b2JointDef& definition) {
    return asWorld(world)->world->CreateJoint(&definition);
}

} // namespace

// ---------------------------------------------------------------------------------------------
// Creation
// ---------------------------------------------------------------------------------------------

// Rotation around a shared point. `referenceAngle` is bodyB's angle minus bodyA's at rest.
KB2_EXPORT void* kb2_joint_revolute(void* world, void* bodyA, void* bodyB, float ax, float ay,
                                    float bx, float by, int collideConnected,
                                    float referenceAngle) {
    b2RevoluteJointDef definition;
    setBodies(definition, bodyA, bodyB, collideConnected);
    definition.localAnchorA = localAnchor(bodyA, ax, ay);
    definition.localAnchorB = localAnchor(bodyB, bx, by);
    definition.referenceAngle = referenceAngle;
    return create(world, definition);
}

// Translation along the world axis (axisX, axisY) without rotation.
KB2_EXPORT void* kb2_joint_prismatic(void* world, void* bodyA, void* bodyB, float ax, float ay,
                                     float bx, float by, float axisX, float axisY,
                                     int collideConnected, float referenceAngle) {
    b2PrismaticJointDef definition;
    setBodies(definition, bodyA, bodyB, collideConnected);
    definition.localAnchorA = localAnchor(bodyA, ax, ay);
    definition.localAnchorB = localAnchor(bodyB, bx, by);
    definition.localAxisA = localAxis(bodyA, axisX, axisY);
    definition.referenceAngle = referenceAngle;
    return create(world, definition);
}

KB2_EXPORT void* kb2_joint_weld(void* world, void* bodyA, void* bodyB, float ax, float ay,
                                float bx, float by, int collideConnected, float referenceAngle) {
    b2WeldJointDef definition;
    setBodies(definition, bodyA, bodyB, collideConnected);
    definition.localAnchorA = localAnchor(bodyA, ax, ay);
    definition.localAnchorB = localAnchor(bodyB, bx, by);
    definition.referenceAngle = referenceAngle;
    return create(world, definition);
}

// Keeps the anchors at most `maxLength` apart.
KB2_EXPORT void* kb2_joint_rope(void* world, void* bodyA, void* bodyB, float ax, float ay,
                                float bx, float by, float maxLength, int collideConnected) {
    b2RopeJointDef definition;
    setBodies(definition, bodyA, bodyB, collideConnected);
    definition.localAnchorA = localAnchor(bodyA, ax, ay);
    definition.localAnchorB = localAnchor(bodyB, bx, by);
    definition.maxLength = maxLength;
    return create(world, definition);
}

// Keeps the anchors at their current distance.
KB2_EXPORT void* kb2_joint_distance(void* world, void* bodyA, void* bodyB, float ax, float ay,
                                    float bx, float by, int collideConnected) {
    b2DistanceJointDef definition;
    definition.Initialize(asBody(bodyA), asBody(bodyB), b2Vec2(ax, ay), b2Vec2(bx, by));
    definition.collideConnected = collideConnected != 0;
    return create(world, definition);
}

// A wheel: bodyB moves along the axis on a spring and rotates freely.
KB2_EXPORT void* kb2_joint_wheel(void* world, void* bodyA, void* bodyB, float ax, float ay,
                                 float bx, float by, float axisX, float axisY,
                                 int collideConnected) {
    b2WheelJointDef definition;
    setBodies(definition, bodyA, bodyB, collideConnected);
    definition.localAnchorA = localAnchor(bodyA, ax, ay);
    definition.localAnchorB = localAnchor(bodyB, bx, by);
    definition.localAxisA = localAxis(bodyA, axisX, axisY);
    return create(world, definition);
}

// Top-down friction: resists relative motion up to a maximum force and torque.
KB2_EXPORT void* kb2_joint_friction(void* world, void* bodyA, void* bodyB, float ax, float ay,
                                    float bx, float by, int collideConnected) {
    b2FrictionJointDef definition;
    setBodies(definition, bodyA, bodyB, collideConnected);
    definition.localAnchorA = localAnchor(bodyA, ax, ay);
    definition.localAnchorB = localAnchor(bodyB, bx, by);
    return create(world, definition);
}

// Drives bodyB towards an offset from bodyA (starting at their current relative placement).
KB2_EXPORT void* kb2_joint_motor(void* world, void* bodyA, void* bodyB, float correctionFactor,
                                 int collideConnected) {
    b2MotorJointDef definition;
    definition.Initialize(asBody(bodyA), asBody(bodyB));
    definition.collideConnected = collideConnected != 0;
    definition.correctionFactor = correctionFactor;
    return create(world, definition);
}

// Two bodies hanging from fixed ground anchors: lengthA + ratio * lengthB stays constant.
KB2_EXPORT void* kb2_joint_pulley(void* world, void* bodyA, void* bodyB, float groundAX,
                                  float groundAY, float groundBX, float groundBY, float ax,
                                  float ay, float bx, float by, float ratio,
                                  int collideConnected) {
    b2PulleyJointDef definition;
    definition.Initialize(asBody(bodyA), asBody(bodyB), b2Vec2(groundAX, groundAY),
                          b2Vec2(groundBX, groundBY), b2Vec2(ax, ay), b2Vec2(bx, by), ratio);
    definition.collideConnected = collideConnected != 0;
    return create(world, definition);
}

// Couples two revolute/prismatic joints. Box2D requires bodyA/bodyB of the gear to be the
// moving bodies of the two joints, which are their bodyB.
KB2_EXPORT void* kb2_joint_gear(void* world, void* joint1, void* joint2, float ratio,
                                int collideConnected) {
    b2GearJointDef definition;
    definition.joint1 = asJoint(joint1);
    definition.joint2 = asJoint(joint2);
    definition.ratio = ratio;
    definition.collideConnected = collideConnected != 0;
    definition.bodyA = definition.joint1->GetBodyB();
    definition.bodyB = definition.joint2->GetBodyB();
    return create(world, definition);
}

// Pulls `body` towards a world target (dragging with the mouse). The first body is the world's
// ground body; the spring is 5 Hz with 0.7 damping.
KB2_EXPORT void* kb2_joint_mouse(void* world, void* body, float targetX, float targetY,
                                 float maxForce) {
    b2MouseJointDef definition;
    definition.bodyA = asWorld(world)->ground;
    definition.bodyB = asBody(body);
    definition.target.Set(targetX, targetY);
    definition.maxForce = maxForce;
    definition.frequencyHz = 5.0f;
    definition.dampingRatio = 0.7f;
    definition.collideConnected = true;
    return create(world, definition);
}

KB2_EXPORT void kb2_joint_destroy(void* world, void* joint) {
    asWorld(world)->world->DestroyJoint(asJoint(joint));
}

// ---------------------------------------------------------------------------------------------
// Common properties
// ---------------------------------------------------------------------------------------------

KB2_EXPORT void kb2_joint_set_userid(void* joint, intptr_t id) {
    asJoint(joint)->SetUserData(reinterpret_cast<void*>(id));
}

// Box2D's b2JointType value (e_revoluteJoint = 1 ... e_motorJoint = 11).
KB2_EXPORT int kb2_joint_type(void* joint) {
    return static_cast<int>(asJoint(joint)->GetType());
}

// out: { bodyA, bodyB }
KB2_EXPORT void kb2_joint_bodies(void* joint, void** out) {
    out[0] = asJoint(joint)->GetBodyA();
    out[1] = asJoint(joint)->GetBodyB();
}

// out: { anchorA.x, anchorA.y, anchorB.x, anchorB.y } in world coordinates.
KB2_EXPORT void kb2_joint_anchors(void* joint, float* out) {
    writeVec(out, asJoint(joint)->GetAnchorA());
    writeVec(out + 2, asJoint(joint)->GetAnchorB());
}

// out: { force.x, force.y, torque } the joint applied over the last step (inverseDt = 1 / dt).
KB2_EXPORT void kb2_joint_reaction(void* joint, float inverseDt, float* out) {
    writeVec(out, asJoint(joint)->GetReactionForce(inverseDt));
    out[2] = asJoint(joint)->GetReactionTorque(inverseDt);
}

KB2_EXPORT int kb2_joint_collide(void* joint) {
    return asJoint(joint)->GetCollideConnected();
}

// ---------------------------------------------------------------------------------------------
// Scalar properties (JointProperty codes). One reader and one writer per joint type: `found` /
// the return value tell whether the type has the property.
// ---------------------------------------------------------------------------------------------

namespace {

bool getRevolute(b2RevoluteJoint* j, int property, float& value) {
    switch (property) {
    case JOINT_VALUE: value = j->GetJointAngle(); return true;
    case JOINT_SPEED: value = j->GetJointSpeed(); return true;
    case JOINT_LIMIT_ENABLED: value = j->IsLimitEnabled(); return true;
    case JOINT_LOWER_LIMIT: value = j->GetLowerLimit(); return true;
    case JOINT_UPPER_LIMIT: value = j->GetUpperLimit(); return true;
    case JOINT_MOTOR_ENABLED: value = j->IsMotorEnabled(); return true;
    case JOINT_MOTOR_SPEED: value = j->GetMotorSpeed(); return true;
    case JOINT_MAX_MOTOR: value = j->GetMaxMotorTorque(); return true;
    case JOINT_REFERENCE_ANGLE: value = j->GetReferenceAngle(); return true;
    }
    return false;
}

bool getPrismatic(b2PrismaticJoint* j, int property, float& value) {
    switch (property) {
    case JOINT_VALUE: value = j->GetJointTranslation(); return true;
    case JOINT_SPEED: value = j->GetJointSpeed(); return true;
    case JOINT_LIMIT_ENABLED: value = j->IsLimitEnabled(); return true;
    case JOINT_LOWER_LIMIT: value = j->GetLowerLimit(); return true;
    case JOINT_UPPER_LIMIT: value = j->GetUpperLimit(); return true;
    case JOINT_MOTOR_ENABLED: value = j->IsMotorEnabled(); return true;
    case JOINT_MOTOR_SPEED: value = j->GetMotorSpeed(); return true;
    case JOINT_MAX_MOTOR: value = j->GetMaxMotorForce(); return true;
    case JOINT_REFERENCE_ANGLE: value = j->GetReferenceAngle(); return true;
    }
    return false;
}

bool getWheel(b2WheelJoint* j, int property, float& value) {
    switch (property) {
    case JOINT_VALUE: value = j->GetJointTranslation(); return true;
    case JOINT_SPEED: value = j->GetJointSpeed(); return true;
    case JOINT_MOTOR_ENABLED: value = j->IsMotorEnabled(); return true;
    case JOINT_MOTOR_SPEED: value = j->GetMotorSpeed(); return true;
    case JOINT_MAX_MOTOR: value = j->GetMaxMotorTorque(); return true;
    case JOINT_FREQUENCY: value = j->GetSpringFrequencyHz(); return true;
    case JOINT_DAMPING_RATIO: value = j->GetSpringDampingRatio(); return true;
    }
    return false;
}

bool getDistance(b2DistanceJoint* j, int property, float& value) {
    switch (property) {
    case JOINT_LENGTH: value = j->GetLength(); return true;
    case JOINT_FREQUENCY: value = j->GetFrequency(); return true;
    case JOINT_DAMPING_RATIO: value = j->GetDampingRatio(); return true;
    }
    return false;
}

bool getWeld(b2WeldJoint* j, int property, float& value) {
    switch (property) {
    case JOINT_FREQUENCY: value = j->GetFrequency(); return true;
    case JOINT_DAMPING_RATIO: value = j->GetDampingRatio(); return true;
    case JOINT_REFERENCE_ANGLE: value = j->GetReferenceAngle(); return true;
    }
    return false;
}

bool getRope(b2RopeJoint* j, int property, float& value) {
    if (property == JOINT_LENGTH) {
        value = j->GetMaxLength();
        return true;
    }
    return false;
}

bool getFriction(b2FrictionJoint* j, int property, float& value) {
    switch (property) {
    case JOINT_MAX_FORCE: value = j->GetMaxForce(); return true;
    case JOINT_MAX_TORQUE: value = j->GetMaxTorque(); return true;
    }
    return false;
}

bool getMotor(b2MotorJoint* j, int property, float& value) {
    switch (property) {
    case JOINT_MAX_FORCE: value = j->GetMaxForce(); return true;
    case JOINT_MAX_TORQUE: value = j->GetMaxTorque(); return true;
    case JOINT_CORRECTION: value = j->GetCorrectionFactor(); return true;
    case JOINT_ANGULAR_OFFSET: value = j->GetAngularOffset(); return true;
    }
    return false;
}

bool getPulley(b2PulleyJoint* j, int property, float& value) {
    switch (property) {
    case JOINT_LENGTH_A: value = j->GetLengthA(); return true;
    case JOINT_LENGTH_B: value = j->GetLengthB(); return true;
    case JOINT_RATIO: value = j->GetRatio(); return true;
    }
    return false;
}

bool getGear(b2GearJoint* j, int property, float& value) {
    if (property == JOINT_RATIO) {
        value = j->GetRatio();
        return true;
    }
    return false;
}

bool getMouse(b2MouseJoint* j, int property, float& value) {
    switch (property) {
    case JOINT_MAX_FORCE: value = j->GetMaxForce(); return true;
    case JOINT_FREQUENCY: value = j->GetFrequency(); return true;
    case JOINT_DAMPING_RATIO: value = j->GetDampingRatio(); return true;
    }
    return false;
}

void setRevolute(b2RevoluteJoint* j, int property, float value) {
    switch (property) {
    case JOINT_LIMIT_ENABLED: j->EnableLimit(value != 0); break;
    case JOINT_MOTOR_ENABLED: j->EnableMotor(value != 0); break;
    case JOINT_MOTOR_SPEED: j->SetMotorSpeed(value); break;
    case JOINT_MAX_MOTOR: j->SetMaxMotorTorque(value); break;
    }
}

void setPrismatic(b2PrismaticJoint* j, int property, float value) {
    switch (property) {
    case JOINT_LIMIT_ENABLED: j->EnableLimit(value != 0); break;
    case JOINT_MOTOR_ENABLED: j->EnableMotor(value != 0); break;
    case JOINT_MOTOR_SPEED: j->SetMotorSpeed(value); break;
    case JOINT_MAX_MOTOR: j->SetMaxMotorForce(value); break;
    }
}

void setWheel(b2WheelJoint* j, int property, float value) {
    switch (property) {
    case JOINT_MOTOR_ENABLED: j->EnableMotor(value != 0); break;
    case JOINT_MOTOR_SPEED: j->SetMotorSpeed(value); break;
    case JOINT_MAX_MOTOR: j->SetMaxMotorTorque(value); break;
    case JOINT_FREQUENCY: j->SetSpringFrequencyHz(value); break;
    case JOINT_DAMPING_RATIO: j->SetSpringDampingRatio(value); break;
    }
}

void setDistance(b2DistanceJoint* j, int property, float value) {
    switch (property) {
    case JOINT_LENGTH: j->SetLength(value); break;
    case JOINT_FREQUENCY: j->SetFrequency(value); break;
    case JOINT_DAMPING_RATIO: j->SetDampingRatio(value); break;
    }
}

void setWeld(b2WeldJoint* j, int property, float value) {
    switch (property) {
    case JOINT_FREQUENCY: j->SetFrequency(value); break;
    case JOINT_DAMPING_RATIO: j->SetDampingRatio(value); break;
    }
}

void setRope(b2RopeJoint* j, int property, float value) {
    if (property == JOINT_LENGTH) {
        j->SetMaxLength(value);
    }
}

void setFriction(b2FrictionJoint* j, int property, float value) {
    switch (property) {
    case JOINT_MAX_FORCE: j->SetMaxForce(value); break;
    case JOINT_MAX_TORQUE: j->SetMaxTorque(value); break;
    }
}

void setMotor(b2MotorJoint* j, int property, float value) {
    switch (property) {
    case JOINT_MAX_FORCE: j->SetMaxForce(value); break;
    case JOINT_MAX_TORQUE: j->SetMaxTorque(value); break;
    case JOINT_CORRECTION: j->SetCorrectionFactor(value); break;
    case JOINT_ANGULAR_OFFSET: j->SetAngularOffset(value); break;
    }
}

void setMouse(b2MouseJoint* j, int property, float value) {
    switch (property) {
    case JOINT_MAX_FORCE: j->SetMaxForce(value); break;
    case JOINT_FREQUENCY: j->SetFrequency(value); break;
    case JOINT_DAMPING_RATIO: j->SetDampingRatio(value); break;
    }
}

} // namespace

// Returns 0 when the joint type has no such property.
KB2_EXPORT float kb2_joint_get(void* joint, int property) {
    b2Joint* j = asJoint(joint);
    float value = 0;
    switch (j->GetType()) {
    case e_revoluteJoint: getRevolute(static_cast<b2RevoluteJoint*>(j), property, value); break;
    case e_prismaticJoint: getPrismatic(static_cast<b2PrismaticJoint*>(j), property, value); break;
    case e_wheelJoint: getWheel(static_cast<b2WheelJoint*>(j), property, value); break;
    case e_distanceJoint: getDistance(static_cast<b2DistanceJoint*>(j), property, value); break;
    case e_weldJoint: getWeld(static_cast<b2WeldJoint*>(j), property, value); break;
    case e_ropeJoint: getRope(static_cast<b2RopeJoint*>(j), property, value); break;
    case e_frictionJoint: getFriction(static_cast<b2FrictionJoint*>(j), property, value); break;
    case e_motorJoint: getMotor(static_cast<b2MotorJoint*>(j), property, value); break;
    case e_pulleyJoint: getPulley(static_cast<b2PulleyJoint*>(j), property, value); break;
    case e_gearJoint: getGear(static_cast<b2GearJoint*>(j), property, value); break;
    case e_mouseJoint: getMouse(static_cast<b2MouseJoint*>(j), property, value); break;
    default: break;
    }
    return value;
}

// Ignored when the joint type has no such property or the property is read only.
KB2_EXPORT void kb2_joint_set(void* joint, int property, float value) {
    b2Joint* j = asJoint(joint);
    switch (j->GetType()) {
    case e_revoluteJoint: setRevolute(static_cast<b2RevoluteJoint*>(j), property, value); break;
    case e_prismaticJoint: setPrismatic(static_cast<b2PrismaticJoint*>(j), property, value); break;
    case e_wheelJoint: setWheel(static_cast<b2WheelJoint*>(j), property, value); break;
    case e_distanceJoint: setDistance(static_cast<b2DistanceJoint*>(j), property, value); break;
    case e_weldJoint: setWeld(static_cast<b2WeldJoint*>(j), property, value); break;
    case e_ropeJoint: setRope(static_cast<b2RopeJoint*>(j), property, value); break;
    case e_frictionJoint: setFriction(static_cast<b2FrictionJoint*>(j), property, value); break;
    case e_motorJoint: setMotor(static_cast<b2MotorJoint*>(j), property, value); break;
    case e_mouseJoint: setMouse(static_cast<b2MouseJoint*>(j), property, value); break;
    default: break; // pulley and gear have no settable properties
    }
}

// Lower and upper limit of a revolute (radians) or prismatic (meters) joint; ignored otherwise.
KB2_EXPORT void kb2_joint_set_limits(void* joint, float lower, float upper) {
    b2Joint* j = asJoint(joint);
    if (j->GetType() == e_revoluteJoint) {
        static_cast<b2RevoluteJoint*>(j)->SetLimits(lower, upper);
    } else if (j->GetType() == e_prismaticJoint) {
        static_cast<b2PrismaticJoint*>(j)->SetLimits(lower, upper);
    }
}

// ---------------------------------------------------------------------------------------------
// Vector properties (JointVector codes)
// ---------------------------------------------------------------------------------------------

// Only the motor joint's linear offset and the mouse joint's target can be set.
KB2_EXPORT void kb2_joint_set_vec(void* joint, int property, float x, float y) {
    b2Joint* j = asJoint(joint);
    if (j->GetType() == e_motorJoint && property == JOINT_LINEAR_OFFSET) {
        static_cast<b2MotorJoint*>(j)->SetLinearOffset(b2Vec2(x, y));
    } else if (j->GetType() == e_mouseJoint && property == JOINT_TARGET) {
        static_cast<b2MouseJoint*>(j)->SetTarget(b2Vec2(x, y));
    }
}

// Writes (0, 0) when the joint type has no such vector.
KB2_EXPORT void kb2_joint_get_vec(void* joint, int property, float* out) {
    b2Joint* j = asJoint(joint);
    b2JointType type = j->GetType();
    b2Vec2 value(0, 0);
    if (type == e_motorJoint && property == JOINT_LINEAR_OFFSET) {
        value = static_cast<b2MotorJoint*>(j)->GetLinearOffset();
    } else if (type == e_mouseJoint && property == JOINT_TARGET) {
        value = static_cast<b2MouseJoint*>(j)->GetTarget();
    } else if (type == e_pulleyJoint && property == JOINT_GROUND_ANCHOR_A) {
        value = static_cast<b2PulleyJoint*>(j)->GetGroundAnchorA();
    } else if (type == e_pulleyJoint && property == JOINT_GROUND_ANCHOR_B) {
        value = static_cast<b2PulleyJoint*>(j)->GetGroundAnchorB();
    } else if (type == e_prismaticJoint && property == JOINT_LOCAL_AXIS) {
        value = static_cast<b2PrismaticJoint*>(j)->GetLocalAxisA();
    } else if (type == e_wheelJoint && property == JOINT_LOCAL_AXIS) {
        value = static_cast<b2WheelJoint*>(j)->GetLocalAxisA();
    }
    writeVec(out, value);
}
