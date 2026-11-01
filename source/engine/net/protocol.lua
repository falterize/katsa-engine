-- Message ids and channels shared by Server and Client.
return {
    VERSION = 1,
    -- katsa.net channels
    RELIABLE = 1,
    SEQUENCED = 2,
    UNRELIABLE = 3,
    -- reliable messages
    HELLO = 1,
    WELCOME = 2,
    REJECT = 3,
    SPAWN = 4,
    DESPAWN = 5,
    REMOTE = 6,
    PLAYER_JOIN = 7,
    PLAYER_LEAVE = 8,
    REQUEST = 9,
    RESPONSE = 10,
    AUTHORITY = 11,
    -- sequenced messages
    SNAPSHOT = 20,
    INPUT = 21,
    CLIENT_STATE = 22,
}
