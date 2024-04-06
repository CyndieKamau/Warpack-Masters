// Generated by dojo-bindgen on Sat, 6 Apr 2024 07:50:28 +0000. Do not modify this file manually.
using System;
using Dojo;
using Dojo.Starknet;

// Type definition for `warpack_masters::models::CharacterItem::Position` struct
[Serializable]
public struct Position {
    public uint x;
    public uint y;
}


// Model definition for `warpack_masters::models::DummyCharacterItem::DummyCharacterItem` model
public class DummyCharacterItem : ModelInstance {
    [ModelField("level")]
    public uint level;

    [ModelField("dummyCharId")]
    public uint dummyCharId;

    [ModelField("counterId")]
    public uint counterId;

    [ModelField("itemId")]
    public uint itemId;

    [ModelField("position")]
    public Position position;

    [ModelField("rotation")]
    public uint rotation;

    // Start is called before the first frame update
    void Start() {
    }

    // Update is called once per frame
    void Update() {
    }
}
        