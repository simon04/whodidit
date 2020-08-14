package whodidit

import (
	"math"

	"github.com/simon04/whodidit/parse_osc/osm"
)

const TILE_SIZE = 0.01

func GetChangeTiles(osmChange *osm.OsmChange) ChangeTileCollection {
	tiles := make(ChangeTileCollection)
	for _, action := range osmChange.Create {
		for _, node := range action.Node {
			idx := NewChangeTileIndex(node)
			tile := tiles.GetOrCreate(idx)
			tile.NodesCreated++
		}
	}
	for _, action := range osmChange.Delete {
		for _, node := range action.Node {
			idx := NewChangeTileIndex(node)
			tile := tiles.GetOrCreate(idx)
			tile.NodesDeleted++
		}
	}
	for _, action := range osmChange.Modify {
		for _, node := range action.Node {
			idx := NewChangeTileIndex(node)
			tile := tiles.GetOrCreate(idx)
			tile.NodesModified++
		}
	}

	return tiles
}

type ChangeTileCollection map[ChangeTileIndex]*ChangeTile

func (tiles *ChangeTileCollection) GetOrCreate(idx ChangeTileIndex) *ChangeTile {
	tile, ok := (*tiles)[idx]
	if ok {
		return tile
	}
	tile = &ChangeTile{
		ChangeTileIndex: idx,
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
	NodesCreated  uint32
	NodesModified uint32
	NodesDeleted  uint32
}
