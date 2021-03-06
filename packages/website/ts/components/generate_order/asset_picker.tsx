import * as _ from 'lodash';
import Dialog from 'material-ui/Dialog';
import FlatButton from 'material-ui/FlatButton';
import * as React from 'react';
import { Blockchain } from 'ts/blockchain';
import { NewTokenForm } from 'ts/components/generate_order/new_token_form';
import { TrackTokenConfirmation } from 'ts/components/track_token_confirmation';
import { TokenIcon } from 'ts/components/ui/token_icon';
import { trackedTokenStorage } from 'ts/local_storage/tracked_token_storage';
import { Dispatcher } from 'ts/redux/dispatcher';
import { DialogConfigs, Token, TokenByAddress, TokenVisibility } from 'ts/types';

const TOKEN_ICON_DIMENSION = 100;
const TILE_DIMENSION = 146;
enum AssetViews {
    ASSET_PICKER = 'ASSET_PICKER',
    NEW_TOKEN_FORM = 'NEW_TOKEN_FORM',
    CONFIRM_TRACK_TOKEN = 'CONFIRM_TRACK_TOKEN',
}

interface AssetPickerProps {
    userAddress: string;
    blockchain: Blockchain;
    dispatcher: Dispatcher;
    networkId: number;
    isOpen: boolean;
    currentTokenAddress: string;
    onTokenChosen: (tokenAddress: string) => void;
    tokenByAddress: TokenByAddress;
    tokenVisibility?: TokenVisibility;
}

interface AssetPickerState {
    assetView: AssetViews;
    hoveredAddress: string | undefined;
    chosenTrackTokenAddress: string;
    isAddingTokenToTracked: boolean;
}

export class AssetPicker extends React.Component<AssetPickerProps, AssetPickerState> {
    public static defaultProps: Partial<AssetPickerProps> = {
        tokenVisibility: TokenVisibility.ALL,
    };
    private _dialogConfigsByAssetView: { [assetView: string]: DialogConfigs };
    constructor(props: AssetPickerProps) {
        super(props);
        this.state = {
            assetView: AssetViews.ASSET_PICKER,
            hoveredAddress: undefined,
            chosenTrackTokenAddress: undefined,
            isAddingTokenToTracked: false,
        };
        this._dialogConfigsByAssetView = {
            [AssetViews.ASSET_PICKER]: {
                title: 'Select token',
                isModal: false,
                actions: [],
            },
            [AssetViews.NEW_TOKEN_FORM]: {
                title: 'Add an ERC20 token',
                isModal: false,
                actions: [],
            },
            [AssetViews.CONFIRM_TRACK_TOKEN]: {
                title: 'Tracking confirmation',
                isModal: true,
                actions: [
                    <FlatButton
                        key="noTracking"
                        label="No"
                        onTouchTap={this._onTrackConfirmationRespondedAsync.bind(this, false)}
                    />,
                    <FlatButton
                        key="yesTrack"
                        label="Yes"
                        onTouchTap={this._onTrackConfirmationRespondedAsync.bind(this, true)}
                    />,
                ],
            },
        };
    }
    public render() {
        const dialogConfigs: DialogConfigs = this._dialogConfigsByAssetView[this.state.assetView];
        return (
            <Dialog
                title={dialogConfigs.title}
                titleStyle={{ fontWeight: 100 }}
                modal={dialogConfigs.isModal}
                open={this.props.isOpen}
                actions={dialogConfigs.actions}
                onRequestClose={this._onCloseDialog.bind(this)}
            >
                {this.state.assetView === AssetViews.ASSET_PICKER && this._renderAssetPicker()}
                {this.state.assetView === AssetViews.NEW_TOKEN_FORM && (
                    <NewTokenForm
                        blockchain={this.props.blockchain}
                        onNewTokenSubmitted={this._onNewTokenSubmitted.bind(this)}
                        tokenByAddress={this.props.tokenByAddress}
                    />
                )}
                {this.state.assetView === AssetViews.CONFIRM_TRACK_TOKEN && this._renderConfirmTrackToken()}
            </Dialog>
        );
    }
    private _renderConfirmTrackToken() {
        const token = this.props.tokenByAddress[this.state.chosenTrackTokenAddress];
        return (
            <TrackTokenConfirmation
                tokens={[token]}
                tokenByAddress={this.props.tokenByAddress}
                networkId={this.props.networkId}
                isAddingTokenToTracked={this.state.isAddingTokenToTracked}
            />
        );
    }
    private _renderAssetPicker() {
        return (
            <div
                className="clearfix flex flex-wrap"
                style={{
                    overflowY: 'auto',
                    maxWidth: 720,
                    maxHeight: 356,
                    marginBottom: 10,
                }}
            >
                {this._renderGridTiles()}
            </div>
        );
    }
    private _renderGridTiles() {
        let isHovered;
        let tileStyles;
        const gridTiles = _.map(this.props.tokenByAddress, (token: Token, address: string) => {
            if (
                (this.props.tokenVisibility === TokenVisibility.TRACKED && !token.isTracked) ||
                (this.props.tokenVisibility === TokenVisibility.UNTRACKED && token.isTracked)
            ) {
                return null; // Skip
            }
            isHovered = this.state.hoveredAddress === address;
            tileStyles = {
                cursor: 'pointer',
                opacity: isHovered ? 0.6 : 1,
            };
            return (
                <div
                    key={address}
                    style={{
                        width: TILE_DIMENSION,
                        height: TILE_DIMENSION,
                        ...tileStyles,
                    }}
                    className="p2 mx-auto"
                    onClick={this._onChooseToken.bind(this, address)}
                    onMouseEnter={this._onToggleHover.bind(this, address, true)}
                    onMouseLeave={this._onToggleHover.bind(this, address, false)}
                >
                    <div className="p1 center">
                        <TokenIcon token={token} diameter={TOKEN_ICON_DIMENSION} />
                    </div>
                    <div className="center">{token.name}</div>
                </div>
            );
        });
        const otherTokenKey = 'otherToken';
        isHovered = this.state.hoveredAddress === otherTokenKey;
        tileStyles = {
            cursor: 'pointer',
            opacity: isHovered ? 0.6 : 1,
        };
        if (this.props.tokenVisibility !== TokenVisibility.TRACKED) {
            gridTiles.push(
                <div
                    key={otherTokenKey}
                    style={{
                        width: TILE_DIMENSION,
                        height: TILE_DIMENSION,
                        ...tileStyles,
                    }}
                    className="p2 mx-auto"
                    onClick={this._onCustomAssetChosen.bind(this)}
                    onMouseEnter={this._onToggleHover.bind(this, otherTokenKey, true)}
                    onMouseLeave={this._onToggleHover.bind(this, otherTokenKey, false)}
                >
                    <div className="p1 center">
                        <i
                            style={{ fontSize: 105, paddingLeft: 1, paddingRight: 1 }}
                            className="zmdi zmdi-plus-circle"
                        />
                    </div>
                    <div className="center">Other ERC20 Token</div>
                </div>,
            );
        }
        return gridTiles;
    }
    private _onToggleHover(address: string, isHovered: boolean) {
        const hoveredAddress = isHovered ? address : undefined;
        this.setState({
            hoveredAddress,
        });
    }
    private _onCloseDialog() {
        this.setState({
            assetView: AssetViews.ASSET_PICKER,
        });
        this.props.onTokenChosen(this.props.currentTokenAddress);
    }
    private _onChooseToken(tokenAddress: string) {
        const token = this.props.tokenByAddress[tokenAddress];
        if (token.isTracked) {
            this.props.onTokenChosen(tokenAddress);
        } else {
            this.setState({
                assetView: AssetViews.CONFIRM_TRACK_TOKEN,
                chosenTrackTokenAddress: tokenAddress,
            });
        }
    }
    private _onCustomAssetChosen() {
        this.setState({
            assetView: AssetViews.NEW_TOKEN_FORM,
        });
    }
    private _onNewTokenSubmitted(newToken: Token) {
        trackedTokenStorage.addTrackedTokenToUser(this.props.userAddress, this.props.networkId, newToken);
        this.props.dispatcher.addTokenToTokenByAddress(newToken);
        this.setState({
            assetView: AssetViews.ASSET_PICKER,
        });
        this.props.onTokenChosen(newToken.address);
    }
    private async _onTrackConfirmationRespondedAsync(didUserAcceptTracking: boolean) {
        if (!didUserAcceptTracking) {
            this.setState({
                isAddingTokenToTracked: false,
                assetView: AssetViews.ASSET_PICKER,
                chosenTrackTokenAddress: undefined,
            });
            this._onCloseDialog();
            return;
        }
        this.setState({
            isAddingTokenToTracked: true,
        });
        const tokenAddress = this.state.chosenTrackTokenAddress;
        const token = this.props.tokenByAddress[tokenAddress];
        const newTokenEntry = {
            ...token,
        };

        newTokenEntry.isTracked = true;
        trackedTokenStorage.addTrackedTokenToUser(this.props.userAddress, this.props.networkId, newTokenEntry);

        this.props.dispatcher.updateTokenByAddress([newTokenEntry]);
        this.setState({
            isAddingTokenToTracked: false,
            assetView: AssetViews.ASSET_PICKER,
            chosenTrackTokenAddress: undefined,
        });
        this.props.onTokenChosen(tokenAddress);
    }
}
