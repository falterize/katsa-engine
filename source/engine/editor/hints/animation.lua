-- Inspector descriptions of animators, tracks, trees, bones and ramps.
-- Editor text only: the classes carry no hint of their own.
-- Shape: { ClassName = { property = 'text' } }; a subclass inherits its base class entries.
return {
    AnimationTree = {
        active = 'Drives the Animator when on. Turn off to freeze the blend weights.',
        animator = 'The Animator of the model to drive. Empty uses the model this node sits under.',
        state = 'Active state of the root state machine.',
    },
}
