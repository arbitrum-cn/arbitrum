# run this from arbitrum project root
HASH_NOW=$(git rev-parse HEAD)
echo "Currently on commit $HASH_NOW"
HASH_BEFORE=$1
HASH_AFTER=$2
echo "Comparing gas usage between $HASH_BEFORE and $HASH_AFTER"

# checkout before, run tests, create report
git checkout $HASH_BEFORE
cd ./packages/arb-bridge-eth
echo "Measuring gas usage for $HASH_BEFORE"
yarn hardhat clean
yarn hardhat compile
yarn test:gas:ci
cd ../..
mv gasReporterOutput.json ./packages/tools/gas-$HASH_BEFORE.json

# and after
git checkout $HASH_AFTER
cd ./packages/arb-bridge-eth
echo "Measuring gas usage for $HASH_AFTER"
yarn hardhat clean
yarn hardhat compile
yarn test:gas:ci
cd ../..
mv gasReporterOutput.json ./packages/tools/gas-$HASH_AFTER.json

# now compare by running output
echo "Calculating comparison"
echo "./gas-$HASH_BEFORE.json ./gas-$HASH_AFTER.json ./comparison-output.csv"
cd packages/tools
yarn dev:compare-gas -- "./gas-$HASH_BEFORE.json ./gas-$HASH_AFTER.json ./comparison-output.csv"

