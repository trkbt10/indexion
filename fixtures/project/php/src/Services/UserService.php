<?php

namespace App\Services;

use App\Billing\Invoice;
use App\Dto\UserDto;
use GuzzleHttp\Client;

/**
 * Manages user operations.
 */
class UserService
{
    private string $dbHost;
    private Client $http;

    public function __construct(string $dbHost)
    {
        $this->dbHost = $dbHost;
        $this->http = new Client();
    }

    /**
     * Find a user by ID.
     */
    public function findById(int $id): ?UserDto
    {
        return null;
    }

    public function create(UserDto $dto): bool
    {
        return $this->validate($dto);
    }

    private function validate(UserDto $dto): bool
    {
        return $dto->name !== '';
    }

    /**
     * Raise an invoice for a user.
     *
     * `App\Billing\` has its own PSR-4 entry pointing outside `src/`, so
     * this import only resolves when the longer prefix wins over `App\`.
     */
    public function invoiceFor(UserDto $dto, int $minorUnits): Invoice
    {
        $invoice = new Invoice('INV-1', $dto);
        $invoice->addLine($minorUnits);

        return $invoice;
    }
}
