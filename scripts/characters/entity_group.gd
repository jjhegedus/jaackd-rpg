class_name EntityGroup
extends Resource

# A group is the unit of ownership and command.
# Every entity belongs to exactly one group at all times.
# Solo groups (size == 1) are an implementation detail — the UI hides them.

@export var group_id: int = -1

# Shown in UI only when the group has more than one member.
# Empty for solo groups.
@export var display_name: String = ""

# Which network peer owns this group.
# -1 = unclaimed (available in lobby).
@export var owner_peer_id: int = -1

# character_id values of entities in this group.
@export var member_ids: Array[int] = []

# The entity whose world position defines the group's map location.
# Typically the leader or (for solo groups) the only member.
@export var anchor_entity: int = -1

# Regional chunk coords (Vector2i) this group has explored.
# Saved in the manifest. Updated live from fog events during a session.
@export var known_chunks: Array[Vector2i] = []


func is_solo() -> bool:
	return member_ids.size() == 1


func is_claimed() -> bool:
	return owner_peer_id != -1
