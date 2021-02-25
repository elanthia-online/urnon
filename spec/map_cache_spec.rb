require 'spec_helper'
require 'urnon/map/cache'

MAP_MOCK = File.join(__dir__, %[mocks], %[map.json])

RSpec.describe Map::Cache do
  before(:all) { Map::Cache.load(file: MAP_MOCK) }
  let(:map) { JSON.parse(File.read(MAP_MOCK)) }

  it "encodes & decodes" do
    expect(Map::Cache.empty?).to be(false)
    map
      .reject {|room| Map::Cache.dropped?(room["id"])}
      .each {|room|
        decoded = Map::Cache.by_id[room["id"]]

        expect(decoded["title"]).to eq(room["title"])
        expect(decoded["description"]).to eq(room["description"])
        # string -> Array<string>
        if room["paths"].is_a?(String)
          expect(decoded["paths"]).to eq([room["paths"]])
        else
          expect(decoded["paths"]).to eq(room["paths"])
        end

        %w(wayto timeto).each {|magic|
          decoded[magic].each {|edge, val|
            expect(val.to_s).to eq(room[magic][edge].to_s)
          }
        }
      }
  end

  it "fast lookups by tags" do
    rooms = Map::Cache.by_tag["acantha leaf"]
    expect(rooms.size).to be > 1
  end

  it "fast lookups by fingerprint" do
    map
      .reject {|room| Map::Cache.dropped?(room["id"]) }
      .each {|room|
        room["title"].product(
          room["description"],
          room["paths"].is_a?(Array) ? room["paths"] : [room["paths"]])
        .each {|variant|
          title, description, paths = variant
          found_by_fingerprint = Map::Cache.find_by_fingerprint(
            title:       title,
            description: description,
            paths:       paths
          )
          expect(found_by_fingerprint).to(
            include Map::Cache.by_id[room["id"]])
        }
      }
  end
end
