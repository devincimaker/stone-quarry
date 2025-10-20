To-Do:
[ ] create good readme for the system
[ ] deploy into an open repository
[ ] Implementar un TWAP para el vender las rocas.
[ ] Improve docs and clarity of everything. Remove LLM smell
[ ] make the rocks pretty and fully onchain
[ ] Deploy a multisig to use it as the owner of the contract

Doing

Done
[x] The price paid to mint a rock should be used to buy our own token and burn it.
[x] The fragments from each rock should track the actual rock they're copying (with per-rock price support).
[x] Make it so that a person can complete the required money missing and get their portion of rocks up front.
[x] Make the token non-transferable
[x] Remove hook from the quarry constructor.
[x] Deploy the token when we launch the quarry.
[x] Add foundry test to check that the token was deployed correctly and we have the required supply in the quarry.
[x] Add liquidity to uniswap v4
[x] Add a transfer fee to the token (of 1)
[x] Hacer flow de testeo para token tax y non-transfer
[x] Add feature so that the contract can acquire a rock if it has the money.
[x] Make it so that I can mint multiple rocks simulnaneuosly (mini rocks), so if the quarry acquires more rocks, there's more buy pressure.
[x] Add the 10% of rocks that I keep from the mini rocks (I get them but they're locked for a month)
[x] Add feature to wrap the rocks into ERC721 so that people can visualize them on etherscan
[x] make the contract upgradeable
