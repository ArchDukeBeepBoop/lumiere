"""The baked atlases out of a glTF binary, one JPEG per material, beside it:
environments/<model>/<material>.jpg ("hall/baked" -> hall_baked.jpg). The
headset puts each on its material itself (BakedPlace), so the place shows its
light whatever the SDK's glTF loader makes of embedded textures.

    python3 textures.py path/to/model.glb [...]
"""
import json
import os
import struct
import sys


def name_of(material):
    return material.replace("/", "_").replace("@", "_").replace(":", "_") + ".jpg"


def extract(path):
    data = open(path, "rb").read()
    n = struct.unpack("<I", data[12:16])[0]
    gltf = json.loads(data[20:20 + n])
    binary = data[20 + n + 8:]
    out = os.path.splitext(path)[0]
    os.makedirs(out, exist_ok=True)
    for m in gltf.get("materials", []):
        tex = m.get("pbrMetallicRoughness", {}).get("baseColorTexture")
        if tex is None:
            continue
        image = gltf["images"][gltf["textures"][tex["index"]]["source"]]
        view = gltf["bufferViews"][image["bufferView"]]
        start = view.get("byteOffset", 0)
        with open(os.path.join(out, name_of(m["name"])), "wb") as f:
            f.write(binary[start:start + view["byteLength"]])
        print(m["name"], "->", os.path.join(out, name_of(m["name"])), view["byteLength"])


if __name__ == "__main__":
    for p in sys.argv[1:]:
        extract(p)
