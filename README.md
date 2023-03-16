### Setup
- Install the dependencies
```zsh
npm install
```
- Set your private key as an environment variable
```zsh
export PRIVATE_KEY=123
```
- Compile the contracts
```zsh
npx hardhat compile
```

### Testing
```zsh
npx hardhat test
```

### Deploying Manually
- Fund your wallet address with tFIL
- Use the deployment file
```zsh
npx hardhat run scripts/deploy-<contract>.js --network hyperspace
```