
CREATE PROCEDURE DataLoadSimulation.DailyProcessToCreateHistory
    @StartDate                           date
  , @EndDate                             date
  , @AverageNumberOfCustomerOrdersPerDay int
  , @SaturdayPercentageOfNormalWorkDay   int
  , @SundayPercentageOfNormalWorkDay     int
  , @UpdateCustomFields                  bit
  , @IsSilentMode                        bit
  , @AreDatesPrinted                     bit
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CurrentDateTime        datetime2(7) = @StartDate;
    DECLARE @EndOfTime              datetime2(7) =  '99991231 23:59:59.9999999';
    DECLARE @StartingWhen           datetime;
    DECLARE @NumberOfCustomerOrders int;
    DECLARE @IsWeekday              bit;
    DECLARE @IsSaturday             bit;
    DECLARE @IsSunday               bit;
    DECLARE @IsMonday               bit;
    DECLARE @Weekday                int;
    DECLARE @IsStaffOnly            bit;
    DECLARE @DateMessage            nvarchar(256);

    SET DATEFIRST 7;  -- Week begins on Sunday

    EXEC DataLoadSimulation.DeactivateTemporalTablesBeforeDataLoad;

    WHILE @CurrentDateTime <= @EndDate
    BEGIN
        SET @DateMessage = N'Processing '
                         + SUBSTRING(DATENAME(weekday, @CurrentDateTime), 1,3) 
                         + N' ' 
                         + CONVERT(nvarchar(20), @CurrentDateTime, 107)
                         + N' '
                         + CAST(DATEDIFF(DAY, @CurrentDateTime, @EndDate) AS NVARCHAR) 
                         + N' Days Remaining '
                         ;

        IF @AreDatesPrinted <> 0 OR @IsSilentMode = 0
        BEGIN
            PRINT @DateMessage
        END;

      -- Calculate the days of the week - different processing happens on each day
        SET @Weekday = DATEPART(weekday, @CurrentDateTime);
        SET @IsSaturday = 0;
        SET @IsSunday = 0;
        SET @IsMonday = 0;
        SET @IsWeekday = 1;

        IF @Weekday = 7
        BEGIN
            SET @IsSaturday = 1;
            SET @IsWeekday = 0;
        END;
        IF @Weekday = 1
        BEGIN
            SET @IsSunday = 1;
            SET @IsWeekday = 0;
        END;
        IF @Weekday = 2 SET @IsMonday = 1;

    -- Purchase orders
        IF @IsWeekday <> 0
        BEGIN
            IF @IsSilentMode = 0
            BEGIN
                PRINT @DateMessage + N'- Receiving Purchase Orders'
            END;

            -- Start receiving purchase orders at 7AM on weekdays
            SET @StartingWhen = DATEADD(hour, 7, @CurrentDateTime);
            EXEC DataLoadSimulation.ReceivePurchaseOrders @CurrentDateTime, @StartingWhen, @EndOfTime, @IsSilentMode;
        END;

    -- Password changes
        IF @IsSilentMode = 0
        BEGIN
            PRINT @DateMessage + N'- Receiving Changing Passwords'
        END;
        SET @StartingWhen = DATEADD(hour, 8, @CurrentDateTime);
        EXEC DataLoadSimulation.ChangePasswords @CurrentDateTime, @StartingWhen, @EndOfTime, @IsSilentMode;

    -- Activate new website users
        IF @IsSilentMode = 0
        BEGIN
            PRINT @DateMessage + N'- Activating Website Logins'
        END;
        SET @StartingWhen = DATEADD(minute, 10, DATEADD(hour, 8, @CurrentDateTime));
        EXEC DataLoadSimulation.ActivateWebsiteLogons @CurrentDateTime, @StartingWhen, @EndOfTime, @IsSilentMode;

    -- Payments to suppliers
        IF DATEPART(weekday, @CurrentDateTime) = 2
        BEGIN
            IF @IsSilentMode = 0
            BEGIN
                PRINT @DateMessage + N'- Paying Suppliers'
            END;
            SET @StartingWhen = DATEADD(hour, 9, @CurrentDateTime); -- Suppliers are paid on Monday mornings
            EXEC DataLoadSimulation.PaySuppliers @CurrentDateTime, @StartingWhen, @EndOfTime, @IsSilentMode;
        END;

    -- Customer orders received
        SET @StartingWhen = DATEADD(hour, 10, @CurrentDateTime);
        SET @NumberOfCustomerOrders = @AverageNumberOfCustomerOrdersPerDay / 2
                                    + CEILING(RAND() * @AverageNumberOfCustomerOrdersPerDay);
        SET @NumberOfCustomerOrders = CASE DATEPART(weekday, @CurrentDateTime)
                                           WHEN 7
                                           THEN FLOOR(@NumberOfCustomerOrders * @SaturdayPercentageOfNormalWorkDay / 100)
                                           WHEN 1
                                           THEN FLOOR(@NumberOfCustomerOrders * @SundayPercentageOfNormalWorkDay / 100)
                                           ELSE @NumberOfCustomerOrders
                                      END;
		SET @NumberOfCustomerOrders = FLOOR(@NumberOfCustomerOrders * CASE WHEN YEAR(@StartingWhen) = 2010 THEN 1.0
		                                                                   WHEN YEAR(@StartingWhen) = 2011 THEN 1.12
																	       WHEN YEAR(@StartingWhen) = 2012 THEN 1.21
																	       WHEN YEAR(@StartingWhen) = 2013 THEN 1.23
																	       ELSE 1.26
		   						                                       END
                                           );
        IF @IsSilentMode = 0
        BEGIN
            PRINT @DateMessage + N'- Creating Customer Orders'
        END;
        EXEC DataLoadSimulation.CreateCustomerOrders @CurrentDateTime, @StartingWhen, @EndOfTime, @NumberOfCustomerOrders, @IsSilentMode;

    -- Pick any customer orders that can be picked
        IF @IsSilentMode = 0
        BEGIN
            PRINT @DateMessage + N'- Picking Stock for Customer Orders'
        END;
        SET @StartingWhen = DATEADD(hour, 11, @CurrentDateTime);
        EXEC DataLoadSimulation.PickStockForCustomerOrders @CurrentDateTime, @StartingWhen, @EndOfTime, @IsSilentMode;

    -- Process any payments from customers
        IF @Weekday <> 0
        BEGIN
            IF @IsSilentMode = 0
            BEGIN
                PRINT @DateMessage + N'- Process Customer Payments'
            END;
            SET @StartingWhen = DATEADD(minute, 30, DATEADD(hour, 11, @CurrentDateTime));
            EXEC DataLoadSimulation.ProcessCustomerPayments @CurrentDateTime, @StartingWhen, @EndOfTime, @IsSilentMode;
        END;

    -- Invoice orders that have been fully picked
        IF @IsSilentMode = 0
        BEGIN
            PRINT @DateMessage + N'- Invoice Picked Orders'
        END;
        SET @StartingWhen = DATEADD(hour, 12, @CurrentDateTime);
        EXEC DataLoadSimulation.InvoicePickedOrders @CurrentDateTime, @StartingWhen, @EndOfTime, @IsSilentMode;

    -- Place supplier orders
        IF @Weekday <> 0
        BEGIN
            IF @IsSilentMode = 0
            BEGIN
                PRINT @DateMessage + N'- Placing Supplier Orders'
            END;
            SET @StartingWhen = DATEADD(hour, 13, @CurrentDateTime);
            EXEC DataLoadSimulation.PlaceSupplierOrders @CurrentDateTime, @StartingWhen, @EndOfTime, @IsSilentMode;
        END;

    -- End of quarter stock take
        IF     (MONTH(@CurrentDateTime) =  1 AND DAY(@CurrentDateTime) = 31)
            OR (MONTH(@CurrentDateTime) =  4 AND DAY(@CurrentDateTime) = 30)
            OR (MONTH(@CurrentDateTime) =  7 AND DAY(@CurrentDateTime) = 31)
            OR (MONTH(@CurrentDateTime) = 10 AND DAY(@CurrentDateTime) = 31)
        BEGIN
            IF @IsSilentMode = 0
            BEGIN
                PRINT @DateMessage + N'- Performing Stock Take'
            END;
            SET @StartingWhen = DATEADD(hour, 14, @CurrentDateTime);
            EXEC DataLoadSimulation.PerformStocktake @CurrentDateTime, @StartingWhen, @EndOfTime, @IsSilentMode;
        END;

    -- Record invoice deliveries
        IF @IsSilentMode = 0
        BEGIN
            PRINT @DateMessage + N'- Recording Invoice Deliveries'
        END;
        SET @StartingWhen = DATEADD(hour, 7, @CurrentDateTime);
        EXEC DataLoadSimulation.RecordInvoiceDeliveries @CurrentDateTime, @StartingWhen, @EndOfTime, @IsSilentMode;

    -- Add customers
        IF @Weekday <> 0
        BEGIN
            IF @IsSilentMode = 0
            BEGIN
                PRINT @DateMessage + N'- Adding Customers'
            END;
            SET @StartingWhen = DATEADD(hour, 15, @CurrentDateTime);
            EXEC DataLoadSimulation.AddCustomers @CurrentDateTime, @StartingWhen, @EndOfTime, @IsSilentMode;
        END;

     -- Add stock items
        IF @IsSilentMode = 0
        BEGIN
            PRINT @DateMessage + N'- Adding Stock Items'
        END;
        SET @StartingWhen = DATEADD(hour, 16, @CurrentDateTime);
        EXEC DataLoadSimulation.AddStockItems @CurrentDateTime, @StartingWhen, @EndOfTime, @IsSilentMode;

    -- Add special deals
        IF @IsSilentMode = 0
        BEGIN
            PRINT @DateMessage + N'- Adding Special Deals'
        END;
        SET @StartingWhen = DATEADD(hour, 16, @CurrentDateTime);
        EXEC DataLoadSimulation.AddSpecialDeals @CurrentDateTime, @StartingWhen, @EndOfTime, @IsSilentMode;

     -- Temporal changes
        IF @IsSilentMode = 0
        BEGIN
            PRINT @DateMessage + N'- Making Temporal Changes'
        END;
        SET @StartingWhen = DATEADD(hour, 16, @CurrentDateTime);
        EXEC DataLoadSimulation.MakeTemporalChanges @CurrentDateTime, @StartingWhen, @EndOfTime, @IsSilentMode;

    -- Record delivery van temperatures
        IF @CurrentDateTime >= '20100101'
        BEGIN
            IF @IsSilentMode = 0
            BEGIN
                PRINT @DateMessage + N'- Recording Delivery Van Temperatures'
            END;
            SET @StartingWhen = DATEADD(hour, 7, @CurrentDateTime);
            EXEC DataLoadSimulation.RecordDeliveryVanTemperatures 300, 2, @CurrentDateTime, @StartingWhen, @IsSilentMode;
        END;

    -- Record cold room temperatures
        IF @CurrentDateTime >= '20101220'
        BEGIN
            IF @IsSilentMode = 0
            BEGIN
                PRINT @DateMessage + N'- Recording Cold Room Temperatures'
            END;
            EXEC DataLoadSimulation.RecordColdRoomTemperatures 30, 4, @CurrentDateTime, @EndOfTime, @IsSilentMode;
        END;

        IF @IsSilentMode = 0
        BEGIN
            PRINT N' ';
        END;

        SET @CurrentDateTime = DATEADD(day, 1, @CurrentDateTime);
    END; -- of processing each day

    IF @IsSilentMode = 0
    BEGIN
        PRINT N'Updating Custom Fields';
    END;
    IF @UpdateCustomFields <> 0
    BEGIN
        EXEC DataLoadSimulation.UpdateCustomFields @EndDate;
    END;

    IF @IsSilentMode = 0
    BEGIN
        PRINT N'Reactivating Temporal Tables After Data Load ';
    END;
    EXEC DataLoadSimulation.ReactivateTemporalTablesAfterDataLoad;

    IF @IsSilentMode = 0
    BEGIN
        PRINT N'Reseeding All Sequences';
    END;
    EXEC Sequences.ReseedAllSequences;

    -- Ensure RLS is applied
    IF @IsSilentMode = 0
    BEGIN
        PRINT N'Applying Row Level Security';
    END;
    EXEC [Application].Configuration_ApplyRowLevelSecurity

    IF @IsSilentMode = 0
    BEGIN
        PRINT N'Done Creating Wide World Importers Data History';
    END;

END;