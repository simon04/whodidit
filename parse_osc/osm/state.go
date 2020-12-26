package osm

import (
	"bufio"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"
)

const REPLICATION_SERVER = "https://planet.openstreetmap.org/replication"
const stateFile = "./whodidit-state.txt"

func WriteLocalState(state int64) {
	f, err := os.Create(stateFile)
	if err != nil {
		panic(err)
	}
	defer f.Close()
	_, err = fmt.Fprintf(f, "sequenceNumber=%d", state)
	if err != nil {
		panic(err)
	}
}

func GetLocalState() int64 {
	f, err := os.Open(stateFile)
	if err != nil {
		panic(err)
	}
	defer f.Close()
	return parseState(f)
}

func GetServerState() int64 {
	url := REPLICATION_SERVER + "/minute/state.txt"
	log.Printf("Fetching %s...", url)
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		panic(err)
	}
	req.Header.Set("User-Agent", "whodidit")

	res, err := http.DefaultClient.Do(req)
	if err != nil {
		panic(err)
	}
	defer res.Body.Close()
	return parseState(res.Body)
}

func parseState(reader io.Reader) int64 {
	scanner := bufio.NewScanner(reader)
	scanner.Split(bufio.ScanLines)
	for scanner.Scan() {
		text := scanner.Text()
		if !strings.HasPrefix(text, "sequenceNumber=") {
			continue
		}
		numberString := text[len("sequenceNumber="):]
		serverState, _ := strconv.ParseInt(numberString, 10, 0)
		return serverState
	}
	panic("sequenceNumber= not found")
}
