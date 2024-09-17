
pragma solidity >=0.7.0 <0.9.0;

contract StandardIntrospection
{
    string public _lastStandard = "ERC-X";
    bytes  public _lastData;
    uint256 public _lastDataSize;
    uint32 public _lastUINT32;
    
    function identifyTokens(address _token) public returns (address)
    {
        (bool success, bytes memory data) = _token.staticcall(abi.encodeWithSelector(0x5a3b7e42)); // call `standard() returns uint32
        
        if(success && data.length == 32)
        {
            _lastUINT32 = abi.decode(data,(uint32));
            if(abi.decode(data,(uint32)) == uint32(223)) 
            {
                _lastStandard = "ERC-223";
                return address(0);
            }
            if(abi.decode(data,(uint32)) == uint32(20)) 
            {
                _lastStandard = "ERC-20";
                return address(0);
            }
            else 
            {
                _lastStandard = "ERC-20, call failed";
                _lastData     = data;
                return address(0);
            }
        }
        else 
        {
            _lastStandard = "Error Call Failed";
        }
        return address(0);
    }
}
