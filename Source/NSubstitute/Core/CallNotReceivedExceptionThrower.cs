﻿using NSubstitute.Exceptions;

namespace NSubstitute.Core
{
    public class CallNotReceivedExceptionThrower : ICallNotReceivedExceptionThrower
    {
        private readonly ICallFormatter _callFormatter;

        public CallNotReceivedExceptionThrower(ICallFormatter callFormatter)
        {
            _callFormatter = callFormatter;
        }

        public void Throw(ICallSpecification callSpecification)
        {
            throw new CallNotReceivedException("Expected not to receive call: " + callSpecification.Format(_callFormatter));
        }
    }
}