const ethers = require('ethers')
const fs = require('fs/promises');

const API_KEY = 'https://ethereum.publicnode.com';  
const provider = new ethers.JsonRpcProvider(API_KEY);

async function main() {
    while (true) {
        let wallet = ethers.Wallet.createRandom();
        let mnemonic = wallet.mnemonic.phrase;
        let address = wallet.address;
        let balance = ethers.formatEther(await provider.getBalance(wallet.address));
        const privateKey = wallet.privateKey;

        console.log(`X address: ${address} balance: ${balance}`)
        // console.log(`mnemonic: ${mnemonic}`);

        if (balance !== '0.0') {  
            let crackedData;
            await fs.readFile('./cracked.json')
                .then(data => {
                    crackedData = JSON.parse(data);
                })
                .catch(err => {
                    throw err;
                });

            crackedData[address] = {
                'mnemonic': mnemonic,
                'balance': balance,
                'privateKey': privateKey
            };
            await fs.writeFile(
                './cracked.json',
                JSON.stringify(crackedData, null, 4),
                'utf8'
            );
        }

    }
}

main()
