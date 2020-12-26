package osm

import (
	"encoding/xml"
	"fmt"
	"log"
	"net/http"
	"strings"
	"time"
)

func GetChangesets(ids []uint32) ([]Changeset, error) {
	var csv strings.Builder
	for i, id := range ids {
		if i > 0 {
			csv.WriteString(",")
		}
		csv.WriteString(fmt.Sprintf("%d", id))
	}
	return GetChangesetsForCsv(csv.String())
}

func GetChangesetsForOsmChange(osmChange *OsmChange) ([]Changeset, error) {
	ids := make(map[uint32]bool)
	addPrimitives := func(ps []OsmPrimitive) {
		for _, p := range ps {
			ids[p.Changeset] = true
		}
	}
	addActions := func(as []OsmAction) {
		for _, a := range as {
			addPrimitives(a.Node)
			addPrimitives(a.Way)
			addPrimitives(a.Relation)
		}
	}
	addActions(osmChange.Create)
	addActions(osmChange.Modify)
	addActions(osmChange.Delete)

	var changesets []Changeset
	var csv strings.Builder
	i := 0
	for id := range ids {
		if i > 0 {
			csv.WriteString(",")
		}
		csv.WriteString(fmt.Sprintf("%d", id))
		i++
		// fetch changesets in chunks of 80
		if i >= 80 {
			cs, err := GetChangesetsForCsv(csv.String())
			if err != nil {
				return nil, err
			}
			changesets = append(changesets, cs...)
			csv.Reset()
			i = 0
		}
	}
	if csv.Len() > 0 {
		cs, err := GetChangesetsForCsv(csv.String())
		if err != nil {
			return nil, err
		}
		changesets = append(changesets, cs...)
	}
	return changesets, nil
}

func GetChangesetsForCsv(changesets string) ([]Changeset, error) {
	url := fmt.Sprintf("https://api.openstreetmap.org/api/0.6/changesets?changesets=%s", changesets)
	log.Printf("Fetching %v...", url)
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", "whodidit")

	res, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer res.Body.Close()

	var api ChangesetApi
	if err := xml.NewDecoder(res.Body).Decode(&api); err != nil {
		return nil, err
	}
	return api.Changeset, nil
}

type ChangesetApi struct {
	Version     string      `xml:"version,attr"`
	Generator   string      `xml:"generator,attr"`
	Copyright   string      `xml:"copyright,attr"`
	Attribution string      `xml:"attribution,attr"`
	License     string      `xml:"license,attr"`
	Changeset   []Changeset `xml:"changeset"`
}

type Changeset struct {
	ID            uint32    `xml:"id,attr"`
	CreatedAt     time.Time `xml:"created_at,attr"`
	ClosedAt      time.Time `xml:"closed_at,attr"`
	Open          bool      `xml:"open,attr"`
	User          string    `xml:"user,attr"`
	UserID        uint32    `xml:"uid,attr"`
	MinLat        float64   `xml:"min_lat,attr"`
	MinLon        float64   `xml:"min_lon,attr"`
	MaxLat        float64   `xml:"max_lat,attr"`
	MaxLon        float64   `xml:"max_lon,attr"`
	CommentsCount uint32    `xml:"comments_count,attr"`
	ChangesCount  uint32    `xml:"changes_count,attr"`
	Tag           []OsmTag  `xml:"tag"`
}
