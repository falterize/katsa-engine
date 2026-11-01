import oimo.collision.broadphase.BroadPhase;
import oimo.collision.geometry.Geometry;
import oimo.collision.geometry.ConvexGeometry;
import oimo.collision.broadphase.BroadPhaseProxyCallback;
import oimo.collision.broadphase.BroadPhaseType;
import oimo.collision.broadphase.Proxy;
import oimo.collision.broadphase.ProxyPair;
import oimo.collision.broadphase.bruteforce.BruteForceBroadPhase;
import oimo.collision.broadphase.bvh.BvhBroadPhase;
import oimo.collision.geometry.Aabb;
import oimo.collision.geometry.BoxGeometry;
import oimo.collision.geometry.CapsuleGeometry;
import oimo.collision.geometry.ConeGeometry;
import oimo.collision.geometry.ConvexHullGeometry;
import oimo.collision.geometry.CylinderGeometry;
import oimo.collision.geometry.GeometryType;
import oimo.collision.geometry.RayCastHit;
import oimo.collision.geometry.SphereGeometry;
import oimo.collision.narrowphase.CollisionMatrix;
import oimo.collision.narrowphase.DetectorResult;
import oimo.collision.narrowphase.DetectorResultPoint;
import oimo.collision.narrowphase.detector.Detector;
import oimo.collision.narrowphase.detector.BoxBoxDetector;
import oimo.collision.narrowphase.detector.CapsuleCapsuleDetector;
import oimo.collision.narrowphase.detector.GjkEpaDetector;
import oimo.collision.narrowphase.detector.SphereBoxDetector;
import oimo.collision.narrowphase.detector.SphereCapsuleDetector;
import oimo.collision.narrowphase.detector.SphereSphereDetector;
import oimo.common.Vec3;
import oimo.common.Transform;
import oimo.common.Setting;
import oimo.collision.narrowphase.detector.gjkepa.GjkEpa;
import oimo.collision.narrowphase.detector.gjkepa.GjkEpaResultState;
import oimo.collision.narrowphase.detector.gjkepa.SimplexUtil;
import oimo.common.Mat3;
import oimo.common.Mat4;
import oimo.common.MathUtil;
import oimo.common.Pool;
import oimo.common.Quat;
import oimo.dynamics.Contact;
import oimo.dynamics.ContactLink;
import oimo.dynamics.ContactManager;
import oimo.dynamics.TimeStep;
import oimo.dynamics.World;
import oimo.dynamics.callback.AabbTestCallback;
import oimo.dynamics.callback.ContactCallback;
import oimo.dynamics.callback.RayCastCallback;
import oimo.dynamics.callback.RayCastClosest;
import oimo.dynamics.common.DebugDraw;
import oimo.dynamics.common.DebugDrawStyle;
import oimo.dynamics.common.Performance;
import oimo.dynamics.constraint.ConstraintSolver;
import oimo.dynamics.constraint.PositionCorrectionAlgorithm;
import oimo.dynamics.constraint.contact.ContactConstraint;
import oimo.dynamics.constraint.contact.Manifold;
import oimo.dynamics.constraint.contact.ManifoldPoint;
import oimo.dynamics.constraint.joint.Joint;
import oimo.dynamics.constraint.joint.CylindricalJoint;
import oimo.dynamics.constraint.joint.JointConfig;
import oimo.dynamics.constraint.joint.CylindricalJointConfig;
import oimo.dynamics.constraint.joint.GenericJoint;
import oimo.dynamics.constraint.joint.GenericJointConfig;
import oimo.dynamics.constraint.joint.JointLink;
import oimo.dynamics.constraint.joint.JointType;
import oimo.dynamics.constraint.joint.PrismaticJoint;
import oimo.dynamics.constraint.joint.PrismaticJointConfig;
import oimo.dynamics.constraint.joint.RagdollJoint;
import oimo.dynamics.constraint.joint.RagdollJointConfig;
import oimo.dynamics.constraint.joint.RevoluteJoint;
import oimo.dynamics.constraint.joint.RevoluteJointConfig;
import oimo.dynamics.constraint.joint.RotationalLimitMotor;
import oimo.dynamics.constraint.joint.SphericalJoint;
import oimo.dynamics.constraint.joint.SphericalJointConfig;
import oimo.dynamics.constraint.joint.SpringDamper;
import oimo.dynamics.constraint.joint.TranslationalLimitMotor;
import oimo.dynamics.constraint.joint.UniversalJoint;
import oimo.dynamics.constraint.joint.UniversalJointConfig;
import oimo.dynamics.constraint.solver.ConstraintSolverType;
import oimo.dynamics.constraint.solver.direct.DirectJointConstraintSolver;
import oimo.dynamics.constraint.solver.pgs.PgsContactConstraintSolver;
import oimo.dynamics.constraint.solver.pgs.PgsJointConstraintSolver;
import oimo.dynamics.rigidbody.MassData;
import oimo.dynamics.rigidbody.RigidBody;
import oimo.dynamics.rigidbody.RigidBodyConfig;
import oimo.dynamics.rigidbody.RigidBodyType;
import oimo.dynamics.rigidbody.Shape;
import oimo.dynamics.rigidbody.ShapeConfig;

class Main {
 static function main() {
 untyped __lua__("_G.OimoExports = {0}", {
BroadPhase:BroadPhase,
Geometry:Geometry,
ConvexGeometry:ConvexGeometry,
BroadPhaseProxyCallback:BroadPhaseProxyCallback,
BroadPhaseType:BroadPhaseType,
Proxy:Proxy,
ProxyPair:ProxyPair,
BruteForceBroadPhase:BruteForceBroadPhase,
BvhBroadPhase:BvhBroadPhase,
Aabb:Aabb,
BoxGeometry:BoxGeometry,
CapsuleGeometry:CapsuleGeometry,
ConeGeometry:ConeGeometry,
ConvexHullGeometry:ConvexHullGeometry,
CylinderGeometry:CylinderGeometry,
GeometryType:GeometryType,
RayCastHit:RayCastHit,
SphereGeometry:SphereGeometry,
CollisionMatrix:CollisionMatrix,
DetectorResult:DetectorResult,
DetectorResultPoint:DetectorResultPoint,
Detector:Detector,
BoxBoxDetector:BoxBoxDetector,
CapsuleCapsuleDetector:CapsuleCapsuleDetector,
GjkEpaDetector:GjkEpaDetector,
SphereBoxDetector:SphereBoxDetector,
SphereCapsuleDetector:SphereCapsuleDetector,
SphereSphereDetector:SphereSphereDetector,
Vec3:Vec3,
Transform:Transform,
Setting:Setting,
GjkEpa:GjkEpa,
GjkEpaResultState:GjkEpaResultState,
SimplexUtil:SimplexUtil,
Mat3:Mat3,
Mat4:Mat4,
MathUtil:MathUtil,
Pool:Pool,
Quat:Quat,
Contact:Contact,
ContactLink:ContactLink,
ContactManager:ContactManager,
TimeStep:TimeStep,
World:World,
AabbTestCallback:AabbTestCallback,
ContactCallback:ContactCallback,
RayCastCallback:RayCastCallback,
RayCastClosest:RayCastClosest,
DebugDraw:DebugDraw,
DebugDrawStyle:DebugDrawStyle,
Performance:Performance,
ConstraintSolver:ConstraintSolver,
PositionCorrectionAlgorithm:PositionCorrectionAlgorithm,
ContactConstraint:ContactConstraint,
Manifold:Manifold,
ManifoldPoint:ManifoldPoint,
Joint:Joint,
CylindricalJoint:CylindricalJoint,
JointConfig:JointConfig,
CylindricalJointConfig:CylindricalJointConfig,
GenericJoint:GenericJoint,
GenericJointConfig:GenericJointConfig,
JointLink:JointLink,
JointType:JointType,
PrismaticJoint:PrismaticJoint,
PrismaticJointConfig:PrismaticJointConfig,
RagdollJoint:RagdollJoint,
RagdollJointConfig:RagdollJointConfig,
RevoluteJoint:RevoluteJoint,
RevoluteJointConfig:RevoluteJointConfig,
RotationalLimitMotor:RotationalLimitMotor,
SphericalJoint:SphericalJoint,
SphericalJointConfig:SphericalJointConfig,
SpringDamper:SpringDamper,
TranslationalLimitMotor:TranslationalLimitMotor,
UniversalJoint:UniversalJoint,
UniversalJointConfig:UniversalJointConfig,
ConstraintSolverType:ConstraintSolverType,
DirectJointConstraintSolver:DirectJointConstraintSolver,
PgsContactConstraintSolver:PgsContactConstraintSolver,
PgsJointConstraintSolver:PgsJointConstraintSolver,
MassData:MassData,
RigidBody:RigidBody,
RigidBodyConfig:RigidBodyConfig,
RigidBodyType:RigidBodyType,
Shape:Shape,
ShapeConfig:ShapeConfig
});
 }
}
