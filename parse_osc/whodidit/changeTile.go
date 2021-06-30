package whodidit

import (
	"math"
	"time"

	"github.com/simon04/whodidit/parse_osc/osm"
)

const TILE_SIZE = 0.01

func GetChangeTiles(osmChange *osm.OsmChange, cs []osm.Changeset) (ChangeTileCollection, ChangesetCollection) {
	changesets := make(ChangesetCollection)
	for _, c := range cs {
		changesets[c.ID] = &Changeset{
			c.ID, c.CreatedAt, c.UserID, c.User, "", "",
			0, 0, 0, 0, 0, 0, 0, 0, 0,
		}
		for _, t := range c.Tag {
			if t.Key == "comment" {
				changesets[c.ID].Comment = t.Value
			} else if t.Key == "created_by" {
				changesets[c.ID].CreatedBy = t.Value
			}
		}
	}

	tiles := make(ChangeTileCollection)
	for _, action := range osmChange.Create {
		for _, node := range action.Node {
			idx := NewChangeTileIndex(node)
			tile := tiles.GetOrCreate(idx, node.Timestamp)
			tile.NodesCreated++
			changesets[node.Changeset].NodesCreated++
			changesets[node.Changeset].UpdateTimestamp(node.Timestamp)
		}
		for _, w := range action.Way {
			changesets[w.Changeset].WaysCreated++
			changesets[w.Changeset].UpdateTimestamp(w.Timestamp)
		}
		for _, r := range action.Relation {
			changesets[r.Changeset].RelationsCreated++
			changesets[r.Changeset].UpdateTimestamp(r.Timestamp)
		}
	}
	for _, action := range osmChange.Delete {
		for _, node := range action.Node {
			idx := NewChangeTileIndex(node)
			tile := tiles.GetOrCreate(idx, node.Timestamp)
			tile.NodesDeleted++
			changesets[node.Changeset].NodesDeleted++
			changesets[node.Changeset].UpdateTimestamp(node.Timestamp)
		}
		for _, w := range action.Way {
			changesets[w.Changeset].WaysDeleted++
			changesets[w.Changeset].UpdateTimestamp(w.Timestamp)
		}
		for _, r := range action.Relation {
			changesets[r.Changeset].RelationsDeleted++
			changesets[r.Changeset].UpdateTimestamp(r.Timestamp)
		}
	}
	for _, action := range osmChange.Modify {
		for _, node := range action.Node {
			idx := NewChangeTileIndex(node)
			tile := tiles.GetOrCreate(idx, node.Timestamp)
			tile.NodesModified++
			changesets[node.Changeset].NodesModified++
			changesets[node.Changeset].UpdateTimestamp(node.Timestamp)
		}
		for _, w := range action.Way {
			changesets[w.Changeset].WaysModified++
			changesets[w.Changeset].UpdateTimestamp(w.Timestamp)
		}
		for _, r := range action.Relation {
			changesets[r.Changeset].RelationsModified++
			changesets[r.Changeset].UpdateTimestamp(r.Timestamp)
		}
	}

	return tiles, changesets
}

type ChangeTileCollection map[ChangeTileIndex]*ChangeTile

func (tiles *ChangeTileCollection) GetOrCreate(idx ChangeTileIndex, timestamp time.Time) *ChangeTile {
	tile, ok := (*tiles)[idx]
	if ok {
		return tile
	}
	tile = &ChangeTile{
		ChangeTileIndex: idx,
		Timestamp:       timestamp,
		NodesCreated:    0,
		NodesModified:   0,
		NodesDeleted:    0,
	}
	(*tiles)[idx] = tile
	return tile
}

type ChangeTileIndex struct {
	Lat       int64
	Lon       int64
	Changeset uint32
}

func NewChangeTileIndex(node osm.OsmPrimitive) ChangeTileIndex {
	return ChangeTileIndex{
		Lat:       int64(math.Floor(node.Lat / TILE_SIZE)),
		Lon:       int64(math.Floor(node.Lon / TILE_SIZE)),
		Changeset: node.Changeset,
	}
}

type ChangeTile struct {
	ChangeTileIndex
	Timestamp     time.Time
	NodesCreated  uint32
	NodesModified uint32
	NodesDeleted  uint32
}

type ChangesetCollection map[uint32]*Changeset

type Changeset struct {
	ID                uint32
	Timestamp         time.Time
	UserID            uint32
	User              string
	Comment           string
	CreatedBy         string
	NodesCreated      uint32
	NodesModified     uint32
	NodesDeleted      uint32
	WaysCreated       uint32
	WaysModified      uint32
	WaysDeleted       uint32
	RelationsCreated  uint32
	RelationsModified uint32
	RelationsDeleted  uint32
}

func (c Changeset) UpdateTimestamp(timestamp time.Time) {
	if timestamp.After(c.Timestamp) {
		c.Timestamp = timestamp
	}
}
