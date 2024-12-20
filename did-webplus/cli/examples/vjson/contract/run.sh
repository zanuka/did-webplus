#!/bin/bash -x
set -eo pipefail
IFS=$'\n\t'
# See http://redsymbol.net/articles/unofficial-bash-strict-mode/

DID_WEBPLUS_BIN="$HOME/.cargo/bin/did-webplus"
if [ ! -f "$DID_WEBPLUS_BIN" ]; then
    echo "did-webplus not found at $DID_WEBPLUS_BIN.  Please install it by running 'cargo install --path did-webplus-cli' in the 'did-webplus' repository root dir."
    exit 1
fi

export RUST_BACKTRACE=1
# export RUST_LOG=did-webplus=trace,vjson=trace,debug

function selfhash_source_schema() {
    SCHEMA_SOURCE_JSON="$1.schema-source.json"
    SCHEMA_JSON="$1.schema.json"
    SCHEMA_URL="$1.schema.url"
    cat "$SCHEMA_SOURCE_JSON" | $DID_WEBPLUS_BIN vjson self-hash > "$SCHEMA_JSON"
    # Just to make sure it worked.
    cat "$SCHEMA_JSON" | $DID_WEBPLUS_BIN vjson verify
    # Extract the "$id" field from the schema file.
    cat "$SCHEMA_JSON" | jq -jr '.["$id"]' > "$SCHEMA_URL"

    # Sanity check
    cat "$SCHEMA_JSON" | $DID_WEBPLUS_BIN vjson verify
}

function selfhash_source_vjson() {
    SOURCE_JSON="$1.source.json"
    JSON="$1.json"
    URL="$1.url"
    cat "$SOURCE_JSON" | $DID_WEBPLUS_BIN vjson self-hash > "$JSON"
    # Just to make sure it worked.
    cat "$JSON" | $DID_WEBPLUS_BIN vjson verify
    # Extract the "$id" field from the schema file.
    echo -n 'vjson:///' > "$URL"
    cat "$JSON" | jq -jr '.selfHash' >> "$URL"
}

function didkey_sign_source_vjson() {
    SOURCE_JSON="$1.source.json"
    JSON="$1.json"
    URL="$1.url"
    PRIVATE_KEY_PATH="$2"
    cat "$SOURCE_JSON" | $DID_WEBPLUS_BIN did-key sign vjson --private-key-path "$PRIVATE_KEY_PATH" > "$JSON"
    # Just to make sure it worked.
    cat "$JSON" | $DID_WEBPLUS_BIN vjson verify
    # Extract the "$id" field from the schema file.
    echo -n 'vjson:///' > "$URL"
    cat "$JSON" | jq -jr '.selfHash' >> "$URL"
}

selfhash_source_schema Contract
CONTRACT_SCHEMA_URL=$(cat Contract.schema.url)

selfhash_source_schema SignatureOnContract
SIGNATURE_ON_CONTRACT_SCHEMA_URL=$(cat SignatureOnContract.schema.url)

selfhash_source_schema CompletedContract
COMPLETED_CONTRACT_SCHEMA_URL=$(cat CompletedContract.schema.url)

#
# Now make some content that uses the schemas.
#

ALICE_PRIVATE_KEY_PATH=Alice.priv.pem
if [ ! -f "$ALICE_PRIVATE_KEY_PATH" ]; then
    $DID_WEBPLUS_BIN did-key generate --key-type ed25519 --private-key-path "$ALICE_PRIVATE_KEY_PATH"
fi
ALICE_DID_KEY=$($DID_WEBPLUS_BIN did-key from-private -p "$ALICE_PRIVATE_KEY_PATH")
echo -n "$ALICE_DID_KEY" > Alice.didkey

BOB_PRIVATE_KEY_PATH=Bob.priv.pem
if [ ! -f "$BOB_PRIVATE_KEY_PATH" ]; then
    $DID_WEBPLUS_BIN did-key generate --key-type ed25519 --private-key-path "$BOB_PRIVATE_KEY_PATH"
fi
BOB_DID_KEY=$($DID_WEBPLUS_BIN did-key from-private -p "$BOB_PRIVATE_KEY_PATH")
echo -n "$BOB_DID_KEY" > Bob.didkey

# Create a Contract between Alice and Bob.
cat > RadDeal.source.json << EOM
{
    "\$schema": "$CONTRACT_SCHEMA_URL",
    "title": "A rad deal",
    "body": "This grants Alice the privilege of blobbing upon payment of 5 megachips to Bob",
    "contractees": {
        "$ALICE_DID_KEY": "Alice",
        "$BOB_DID_KEY": "Bob"
    }
}
EOM
selfhash_source_vjson RadDeal
RAD_DEAL_URL=$(cat RadDeal.url)

# Create Alice's signature on the Contract.
cat > AliceSignature.source.json << EOM
{
    "\$schema": "$SIGNATURE_ON_CONTRACT_SCHEMA_URL",
    "contract": "$RAD_DEAL_URL",
    "signedAt": "2024-11-21T07:40:28Z"
}
EOM
didkey_sign_source_vjson AliceSignature $ALICE_PRIVATE_KEY_PATH
ALICE_SIGNATURE_URL=$(cat AliceSignature.url)

# Create Bob's signature on the Contract.
cat > BobSignature.source.json << EOM
{
    "\$schema": "$SIGNATURE_ON_CONTRACT_SCHEMA_URL",
    "contract": "$RAD_DEAL_URL",
    "signedAt": "2024-11-21T08:22:31Z"
}
EOM
didkey_sign_source_vjson BobSignature $BOB_PRIVATE_KEY_PATH
BOB_SIGNATURE_URL=$(cat BobSignature.url)

# Create the Completed Contract.
cat > CompletedRadDeal.source.json << EOM
{
    "\$schema": "$COMPLETED_CONTRACT_SCHEMA_URL",
    "contract": "$RAD_DEAL_URL",
    "signatures": [
        "$ALICE_SIGNATURE_URL",
        "$BOB_SIGNATURE_URL"
    ]
}
EOM
selfhash_source_vjson CompletedRadDeal
COMPLETED_RAD_DEAL_URL=$(cat CompletedRadDeal.url)

#
# Create a markdown document explaining the whole example.
#

cat > README.md << EOM
# VJSON Generation Example

This example demonstrates the use of VJSON to create schemas representing the various parts of a contract between two parties,
and then creates an contract between Alice and Bob using those schemas.

Note that this file was generated by the \`run.sh\` script in this directory, so this file should not be modified directly.

## Schemas

### Schema "Contract" Source

This is what the schema author creates to define the structure of a "Contract".
The VJSON fields will be computed and auto-populated.

\`Contract.schema-source.json\`:
\`\`\`json
$(cat Contract.schema-source.json | jq .)
\`\`\`

### Schema "Contract" Generated

This is the VJSON schema generated from the source schema.  It is self-verifying and its "\$id" field should be
used as the "\$schema" field in the contract VJSON itself.  The "\$schema" field refers to the Default VJSON schema,
and is auto-populated if no "\$schema" field is provided.  The command used to generate this schema is:

    did-webplus vjson self-hash < Contract.schema-source.json > Contract.schema.json

Its output is the following.  Note that the generated VJSON is also stored in the VJSON doc store so that it can
be referenced by other VJSON documents.

\`Contract.schema.json\`:
\`\`\`json
$(cat Contract.schema.json | jq .)
\`\`\`

### Schema "SignatureOnContract" Source

This is what the schema author creates to define the structure of a "SignatureOnContract".

\`SignatureOnContract.schema-source.json\`:
\`\`\`json
$(cat SignatureOnContract.schema-source.json | jq .)
\`\`\`

### Schema "SignatureOnContract" Generated

This is the VJSON schema generated from the source schema.  The command used to generate this schema is:

    did-webplus vjson self-hash < SignatureOnContract.schema-source.json > SignatureOnContract.schema.json

Its output is the following.

\`SignatureOnContract.schema.json\`:
\`\`\`json
$(cat SignatureOnContract.schema.json | jq .)
\`\`\`

### Schema "CompletedContract" Source

This is what the schema author creates to define the structure of a "CompletedContract".

\`CompletedContract.schema-source.json\`:
\`\`\`json
$(cat CompletedContract.schema-source.json | jq .)
\`\`\`

### Schema "CompletedContract" Generated

This is the VJSON schema generated from the source schema.  The command used to generate this schema is:

    did-webplus vjson self-hash < CompletedContract.schema-source.json > CompletedContract.schema.json

Its output is the following.

\`CompletedContract.schema.json\`:
\`\`\`json
$(cat CompletedContract.schema.json | jq .)
\`\`\`

## Content

### "RadDeal" Source

This is what the contract author creates to define the contract between Alice and Bob.  Note that it represents
the DIDs of Alice and Bob so that there is a basis for a cryptographic commitment in the contract itself.
This requires Alice and Bob both have known DIDs to begin with.  For the simplicity of this example, we generate
private keys for Alice and Bob and use their corresponding did:key values as their DIDs using the following commands:

    did-webplus did-key generate --key-type ed25519 --private-key-path Alice.priv.pem
    did-webplus did-key from-private --private-key-path Alice.priv.pem > Alice.didkey

    did-webplus did-key generate --key-type ed25519 --private-key-path Bob.priv.pem
    did-webplus did-key from-private --private-key-path Bob.priv.pem > Bob.didkey

\`Alice.didkey\`:
\`\`\`
$(cat Alice.didkey)
\`\`\`

\`Bob.didkey\`:
\`\`\`
$(cat Bob.didkey)
\`\`\`

Now the contract can be drafted, capturing the DIDs of Alice and Bob.

\`RadDeal.source.json\`:
\`\`\`json
$(cat RadDeal.source.json | jq .)
\`\`\`

### "RadDeal" Generated

This is the VJSON contract generated from the source contract.  The command used to generate this contract is:

    did-webplus vjson self-hash < RadDeal.source.json > RadDeal.json

Its output is the following.

\`RadDeal.json\`:
\`\`\`json
$(cat RadDeal.json | jq .)
\`\`\`

### "AliceSignature" Source

This is what Alice creates to sign the contract.  It refers to the contract being signed by its VJSON URL.

\`AliceSignature.source.json\`:
\`\`\`json
$(cat AliceSignature.source.json | jq .)
\`\`\`

### "AliceSignature" Generated

This is the VJSON signature generated from the source signature.  The command used to generate this signature is:

    did-webplus did-key sign vjson --private-key-path Alice.priv.pem < AliceSignature.source.json > AliceSignature.json

Its output is the following.

\`AliceSignature.json\`:
\`\`\`json
$(cat AliceSignature.json | jq .)
\`\`\`

### "BobSignature" Source

This is what Bob creates to sign the contract.  It refers to the contract being signed by its VJSON URL.

\`BobSignature.source.json\`:
\`\`\`json
$(cat BobSignature.source.json | jq .)
\`\`\`

### "BobSignature" Generated

This is the VJSON signature generated from the source signature.  The command used to generate this signature is:

    did-webplus did-key sign vjson --private-key-path Bob.priv.pem < BobSignature.source.json > BobSignature.json

Its output is the following.

\`BobSignature.json\`:
\`\`\`json
$(cat BobSignature.json | jq .)
\`\`\`

### "CompletedRadDeal" Source

This is what is written to complete the contract.  It refers to the contract and the signatures by their respective VJSON URLs.

\`CompletedRadDeal.source.json\`:
\`\`\`json
$(cat CompletedRadDeal.source.json | jq .)
\`\`\`

### "CompletedRadDeal" Generated

This is the VJSON contract generated from the source contract.  The command used to generate this contract is:

    did-webplus vjson self-hash < CompletedRadDeal.source.json > CompletedRadDeal.json

Its output is the following.

\`CompletedRadDeal.json\`:
\`\`\`json
$(cat CompletedRadDeal.json | jq .)
\`\`\`

## VJSON Doc Store

The result of each VJSON generation and verification is stored in the VJSON doc store, so that when a VJSON document
references another VJSON document, the referenced document can be resolved (and verified if necessary).  These documents
can be retrieved by their VJSON URLs.  For example:

    did-webplus vjson store get "$RAD_DEAL_URL" | jq .

produces:

\`\`\`json
$(did-webplus vjson store get "$RAD_DEAL_URL" | jq .)
\`\`\`

Note that VJSON docs are stored in JCS format (JSON Canonicalization Scheme) to ensure deterministic representation.
In particular, JCS has no newlines, so it's hard to read, thus usage of the \`jq\` command to pretty-print the output.

There is a "Default" schema which is used as the schema any time the "\$schema" field is not provided in a VJSON document.
This schema is stored in the VJSON doc store as well, and can be retrieved by the following command:

    did-webplus vjson default-schema | jq .

produces:

\`\`\`json
$(did-webplus vjson default-schema | jq .)
\`\`\`

The Default schema is special in that it is its own schema; the "\$id\" field is the same as the "\$schema" field.

## Verification

All VJSON documents are verified upon creation.  However, they can be reverified -- or verified by another party -- using 
the \`did-webplus vjson verify\` command.  For example:

    did-webplus vjson verify < RadDeal.json

will verify the RadDeal VJSON document.  The output will be the verified VJSON document:

\`\`\`json
$(did-webplus vjson verify < RadDeal.json | jq .)
\`\`\`

EOM
