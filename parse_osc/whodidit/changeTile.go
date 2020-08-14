package whodidit

import (
	"math"
	"time"

	"github.com/simon04/whodidit/parse_osc/osm"
)

const TILE_SIZE = 0.01

func GetChangeTiles(osmChange *osm.OsmChange) map[ChangeTileIndex]ChangeTile {
	tiles := make(map[ChangeTileIndex]ChangeTile)
	for _, action := range osmChange.Create {
		for _, node := range action.Node {
			idx := ChangeTileIndex{
				Lat:       int64(math.Floor(node.Lat / TILE_SIZE)),
				Lon:       int64(math.Floor(node.Lon / TILE_SIZE)),
				Changeset: node.Changeset,
			}
			tile, ok := tiles[idx]
			if !ok {
				tile = ChangeTile{
					ChangeTileIndex: idx,
					NodesCreated:    0,
					NodesModified:   0,
					NodesDeleted:    0,
					Timestamp:       node.Timestamp,
				}
				tiles[idx] = tile
			}
			tile.NodesCreated++
		}
	}

	return tiles
}

type ChangeTileIndex struct {
	Lat       int64
	Lon       int64
	Changeset uint32
}

type ChangeTile struct {
	ChangeTileIndex
	NodesCreated  uint32
	NodesModified uint32
	NodesDeleted  uint32
	Timestamp     time.Time
}
