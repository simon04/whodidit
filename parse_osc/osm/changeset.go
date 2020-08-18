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
	var url strings.Builder
	url.WriteString("https://api.openstreetmap.org/api/0.6/changesets?changesets=")
	for i, id := range ids {
		if i > 0 {
			url.WriteString(",")
		}
		url.WriteString(fmt.Sprintf("%d", id))
	}
	log.Printf("Fetching %v...", url)
	req, err := http.NewRequest("GET", url.String(), nil)
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
